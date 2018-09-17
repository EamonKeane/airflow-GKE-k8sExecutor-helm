#! /usr/bin/env bash
set -Eeuxo pipefail

VALUES=

for i in "$@"
do
case ${i} in
	-values-file=*|--values-file=*)
    VALUES="${i#*=}"
    ;;
esac
done

if [ -z "$VALUES" ]
then
      echo "Please supply a json values file."
      exit 1
fi

CREATE_AIRFLOW_DB_INSTANCE=$(jq -r .CREATE_AIRFLOW_DB_INSTANCE $VALUES)
RESTORE_AIRFLOW_FROM_BACKUP=$(jq -r .RESTORE_AIRFLOW_FROM_BACKUP $VALUES)
CREATE_AUTOSCALING_POOL=$(jq -r .CREATE_AUTOSCALING_POOL $VALUES)

AIRFLOW_DB_USER=airflow
AIRFLOW_DB_NAME=airflow
AIRFLOW_DB_USER_PASSWORD=$(openssl rand -base64 12)

KUBERNETES_POSTGRES_CLOUDSQLPROXY_SERVICE=airflow-postgresql
KUBERNETES_POSTGRES_CLOUDSQLPROXY_PORT=5432

export CLOUDSDK_CORE_PROJECT=$(jq -r .CLOUDSDK_CORE_PROJECT $VALUES)
export CLOUDSDK_COMPUTE_REGION=$(jq -r .CLOUDSDK_COMPUTE_REGION $VALUES)
export CLOUDSDK_COMPUTE_ZONE=$(jq -r .CLOUDSDK_COMPUTE_ZONE $VALUES)
AIRFLOW_DB_INSTANCE=$(jq -r .AIRFLOW_DB_INSTANCE $VALUES)
K8S_CLUSTER_NAME=$(jq -r .K8S_CLUSTER_NAME $VALUES)
AIRFLOW_BACKUP_INSTANCE=$(jq -r .AIRFLOW_BACKUP_INSTANCE $VALUES)

AIRFLOW_AVAILABILITY_TYPE=$(jq -r .AIRFLOW_AVAILABILITY_TYPE $VALUES)
AIRFLOW_DB_VERSION=$(jq -r .AIRFLOW_DB_VERSION $VALUES)
AIRFLOW_MEMORY=$(jq -r .AIRFLOW_MEMORY $VALUES)
AIRFLOW_CPU=$(jq -r .AIRFLOW_CPU $VALUES)
AIRFLOW_STORAGE_SIZE=$(jq -r .AIRFLOW_STORAGE_SIZE $VALUES)

K8S_CLUSTER_VERSION=$(jq -r .K8S_CLUSTER_VERSION $VALUES)
K8S_MACHINE_TYPE=$(jq -r .K8S_MACHINE_TYPE $VALUES)
K8S_NUM_NODES=$(jq -r .K8S_NUM_NODES $VALUES)
K8S_SCOPES=$(jq -r .K8S_SCOPES $VALUES)
K8S_AUTOSCALING_NODE_POOL=$(jq -r .K8S_AUTOSCALING_NODE_POOL $VALUES)
K8S_DEFAULT_NODE_POOL_LABELS=$(jq -r .K8S_DEFAULT_NODE_POOL_LABELS $VALUES)
K8S_AUTOSCALING_NODE_POOL_LABELS=$(jq -r .K8S_AUTOSCALING_NODE_POOL_LABELS $VALUES)
K8S_AUTOSCALING_MAX_NODES=$(jq -r .K8S_AUTOSCALING_MAX_NODES $VALUES)
K8S_AUTOSCALING_MIN_NODES=$(jq -r .K8S_AUTOSCALING_MIN_NODES $VALUES)

CREATE_NFS_DISK=$(jq -r .CREATE_NFS_DISK $VALUES)
NFS_DISK_SIZE=$(jq -r .NFS_DISK_SIZE $VALUES)
NFS_DISK_NAME=$(jq -r .NFS_DISK_NAME $VALUES)

if $CREATE_AIRFLOW_DB_INSTANCE
then
    gcloud sql instances create $AIRFLOW_DB_INSTANCE \
        --assign-ip \
        --async \
        --availability-type=$AIRFLOW_AVAILABILITY_TYPE \
        --backup-start-time=04:00 \
        --cpu=$AIRFLOW_CPU \
        --database-version=$AIRFLOW_DB_VERSION \
        --gce-zone=$CLOUDSDK_COMPUTE_ZONE \
        --maintenance-window-day=MON \
        --maintenance-window-hour=4 \
        --memory=$AIRFLOW_MEMORY \
        --require-ssl \
        --storage-auto-increase \
        --storage-size=$AIRFLOW_STORAGE_SIZE

fi

gcloud beta container \
    clusters create $K8S_CLUSTER_NAME \
    --zone=$CLOUDSDK_COMPUTE_ZONE \
    --no-enable-basic-auth \
    --issue-client-certificate \
    --enable-legacy-authorization \
    --cluster-version=$K8S_CLUSTER_VERSION \
    --machine-type=$K8S_MACHINE_TYPE \
    --image-type "COS" \
    --disk-type "pd-standard" \
    --disk-size "100" \
    --scopes $(jq -r '.K8S_SCOPES | join(",")' $VALUES) \
    --node-labels=$K8S_DEFAULT_NODE_POOL_LABELS \
    --num-nodes=$K8S_NUM_NODES \
    --no-enable-stackdriver-kubernetes \
    --enable-ip-alias \
    --network "projects/${CLOUDSDK_CORE_PROJECT}/global/networks/default" \
    --subnetwork "projects/${CLOUDSDK_CORE_PROJECT}/regions/${CLOUDSDK_COMPUTE_REGION}/subnetworks/default" \
    --addons HorizontalPodAutoscaling \
    --enable-autoupgrade \
    --enable-autorepair \
    --maintenance-window "04:00"

# Wait for the kubernetes cluster to be ready
sleep 30

if $RESTORE_AIRFLOW_FROM_BACKUP
then
    AIRFLOW_BACKUP_ID=$(gcloud sql backups list \
                        --instance=$AIRFLOW_BACKUP_INSTANCE \
                        --limit=1 \
                        --format json | jq .[0].id --raw-output)

    if [ "$AIRFLOW_BACKUP_ID" != "null" ]
    then
        gcloud sql backups restore $AIRFLOW_BACKUP_ID \
                --async \
                --restore-instance=$AIRFLOW_DB_INSTANCE \
                --backup-instance=$AIRFLOW_BACKUP_INSTANCE \
                --quiet
    fi
else
    gcloud sql databases create $AIRFLOW_DB_NAME \
            --instance=$AIRFLOW_DB_INSTANCE \
            --async
fi

if $CREATE_AUTOSCALING_POOL
then
    gcloud beta container node-pools create $K8S_AUTOSCALING_NODE_POOL \
        --cluster=$K8S_CLUSTER_NAME \
        --zone=$CLOUDSDK_COMPUTE_ZONE \
        --enable-autorepair \
        --enable-autoupgrade \
        --machine-type=$K8S_MACHINE_TYPE \
        --node-labels=$K8S_AUTOSCALING_NODE_POOL_LABELS \
        --node-version=$K8S_CLUSTER_VERSION \
        --num-nodes=0 \
        --preemptible \
        --enable-autoscaling \
        --max-nodes=$K8S_AUTOSCALING_MAX_NODES \
        --min-nodes=$K8S_AUTOSCALING_MIN_NODES \
        --scopes=$(jq -r '.K8S_SCOPES | join(",")' $VALUES)
fi

if $CREATE_AIRFLOW_DB_INSTANCE
then
    gcloud sql users set-password postgres \
        --host "ignore-this-only-for-mysql" \
        --instance $AIRFLOW_DB_INSTANCE \
        --password $AIRFLOW_DB_USER_PASSWORD

    gcloud sql users create $AIRFLOW_DB_USER \
        --instance=$AIRFLOW_DB_INSTANCE \
        --password=$AIRFLOW_DB_USER_PASSWORD
fi

kubectl --namespace kube-system create serviceaccount tiller
kubectl create clusterrolebinding tiller \
                --clusterrole cluster-admin \
                --serviceaccount=kube-system:tiller
helm init --wait --upgrade --service-account tiller

SQL_ALCHEMY_CONN=postgresql+psycopg2://$AIRFLOW_DB_USER:$AIRFLOW_DB_USER_PASSWORD@$KUBERNETES_POSTGRES_CLOUDSQLPROXY_SERVICE:$KUBERNETES_POSTGRES_CLOUDSQLPROXY_PORT/$AIRFLOW_DB_NAME

echo $SQL_ALCHEMY_CONN > /secrets/airflow/sql_alchemy_conn
# Create the fernet key which is needed to decrypt database the database
FERNET_KEY=$(dd if=/dev/urandom bs=32 count=1 2>/dev/null | openssl base64)
echo $FERNET_KEY > /secrets/airflow/fernet-key

kubectl create secret generic airflow \
    --from-file=fernet-key=/secrets/airflow/fernet-key \
    --from-file=sql_alchemy_conn=/secrets/airflow/sql_alchemy_conn

if $CREATE_NFS_DISK
then
    gcloud compute disks create --size=$NFS_DISK_SIZE $NFS_DISK_NAME || true
fi

sed -i.bak "s/pdName:.*/pdName: $NFS_DISK_NAME/g" /airflow/values.yaml
sed -i.bak "s/databaseInstance:.*/databaseInstance: $AIRFLOW_DB_INSTANCE/g" /airflow/values.yaml
sed -i.bak "s/project:.*/project: $CLOUDSDK_CORE_PROJECT/g" /airflow/values.yaml
sed -i.bak "s/region:.*/region: $CLOUDSDK_COMPUTE_REGION/g" /airflow/values.yaml
rm /airflow/values.yaml.bak

helm upgrade \
    --install \
    --wait \
    airflow \
    airflow

NAMESPACE=default
NFS_POD_NAME=$(kubectl get pods --namespace $NAMESPACE -l "role=nfs-server" -o jsonpath="{.items[0].metadata.name}")
kubectl exec -i $NFS_POD_NAME --namespace $NAMESPACE -- /bin/bash -c "mkdir -p /exports/logs;mkdir -p /exports/dags;chmod go+rw /exports/dags;chmod go+rw /exports/logs; ls -ltrah /exports/"

DAGS_FOLDER_LOCAL=/dags
DAGS_FOLDER_REMOTE=/usr/local/airflow/dags
SCHEDULER_POD_NAME=$(kubectl get pods --namespace $NAMESPACE -l "app=airflow,tier=scheduler" -o jsonpath="{.items[0].metadata.name}")
kubectl cp $DAGS_FOLDER_LOCAL $NAMESPACE/$SCHEDULER_POD_NAME:$DAGS_FOLDER_REMOTE