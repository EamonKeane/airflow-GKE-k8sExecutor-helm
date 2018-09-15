#!/usr/bin/env bash
set -Eeuxo pipefail

#### GLOBAL GCP VARIABLES ####


for i in "$@"
do
case ${i} in
    -project=*|--project=*)
    PROJECT="${i#*=}"
    ;;
    -account=*|--account=*)
    ACCOUNT="${i#*=}"
    ;;
    -region=*|--region=*)
    REGION="${i#*=}"
    ;;
    -gce-zone=*|--gce-zone=*)
    GCE_ZONE="${i#*=}"
    ;;
    -database-instance-name=*|--database-instance-name=*)
    DATABASE_INSTANCE_NAME="${i#*=}"
    ;;
    -cloud-filestore-zone=*|--cloud-filestore-zone=*)
    CLOUD_FILESTORE_ZONE="${i#*=}"
    ;;
    -highly-available-=*|--highly-available=*)
    HIGHLY_AVAILABLE="${i#*=}"
    ;;
esac
done

gcloud config set container/new_scopes_behavior true

## Cloud filestore for dags
#https://cloud.google.com/filestore/docs/quickstart-gcloud
# If not creating, see the readme for how to create your own single-file NFS server
CREATE_CLOUD_FILESTORE=TRUE
CLOUD_FILESTORE_NAME=airflow
# The name of the mount directory on cloud filestore (referenced in helm chart)
CLOUD_FILESTORE_SHARE_NAME="airflow"
# Use default so that it is on the same VPC as most of your other resources
CLOUD_FILESTORE_NETWORK="default"
# Use the below range so that the address of 10.0.0.2 can be used in helm chart
CLOUD_FILESTORE_RESERVED_IP="10.0.0.0/29"
# Cloud filestore capacity (this is the lowest available ($250/mo))
CLOUD_FILESTORE_CAPACITY=1TB
# Premium tier requires at least three times the spend ($900/mo)
CLOUD_FILESTORE_TIER=STANDARD

### Airflow Logs bucket. This must be a globally unique name, 
### so add some randomness such as myorg-airflow-1235
### https://cloud.google.com/storage/docs/quickstart-gsutil
CREATE_GOOGLE_STORAGE_BUCKET=FALSE
GOOGLE_LOG_STORAGE_BUCKET=$PROJECT-airflow

#### DATABASE OPTIONS ####
CREATE_CLOUDSQL_DATABASE=FALSE
ACTIVATION_POLICY=always
if [ $HIGHLY_AVAILABLE = "TRUE" ] 
then
  AVAILABILITY_TYPE=regional
else
  AVAILABILITY_TYPE=zonal
fi

CPU=1
MEMORY=4GiB
DATABASE_VERSION=POSTGRES_9_6
STORAGE_SIZE=10
AIRFLOW_DATABASE_NAME=airflow
AIRFLOW_DATABASE_USER=airflow
AIRFLOW_DATABASE_USER_PASSWORD=$(openssl rand -base64 12)
AIRFLOW_DATABASE_POSTGRES_USER_PASSWORD=$(openssl rand -base64 12)

KUBERNETES_POSTGRES_CLOUDSQLPROXY_SERVICE=airflow-postgresql
KUBERNETES_POSTGRES_CLOUDSQLPROXY_PORT=5432

# Database cloudsql IAM role
CLOUDSQL_SERVICE_ACCOUNT=airflowcloudsql
# Roles must be created one at a time using the CLI
CLOUDSQL_ROLE='roles/cloudsql.admin'
STORAGE_ROLE='roles/storage.admin'

#### AIRFLOW CLUSTER OPTIONS ####
# AIRFLOW options for both leader and worker nodes
CLUSTER_NAME="airflow"
CLUSTER_VERSION="1.10.5-gke.0"
IMAGE_TYPE=COS
SCOPES="cloud-platform"
KUBERNETES_KUBECONFIG_SECRET=kubeconfig

# Airflow leader pool options
KUBERNETES_MACHINE_LABELS="app=airflow"
MASTER_KUBERNETES_NODE_LABELS="app=airflow,pool=webScheduler"
LEADER_POOL_NUM_NODES=1
# 'Memory should be a multiple of 256MiB in zone europe-west2-a for custom machine type, while 2MiB is requested.'., invalidResourceUsage.
MACHINE_TYPE="n1-highcpu-4"

# Airflow worker pool options
CREATE_WORKER_POOL=TRUE
WORKER_NODE_POOL_NAME="airflow-workers"
# These labels should match the helm chart .Values.airflowCfg.kubernetesNodeSelectors if you want to scheduler k8s executor pods on the worker pool
WORKER_KUBERNETES_NODE_LABELS="airflow=airflow_workers,pool=preemptible"
WORKER_NODE_MACHINE_TYPE="n1-standard-4"
WORKER_POOL_NUM_NODES=0
WORKER_POOL_MAX_NODES=6 
WORKER_POOL_MIN_NODES=0

# Some of the kubernetes options require use of beta features.
# gcloud config set container/use_v1_api false

### Create the postgres database ###
### https://cloud.google.com/sdk/gcloud/reference/sql/instances/create
if [ $CREATE_CLOUDSQL_DATABASE = "TRUE" ]
then
gcloud sql instances create $DATABASE_INSTANCE_NAME \
    --activation-policy=$ACTIVATION_POLICY \
    --availability-type=$AVAILABILITY_TYPE \
    --cpu=$CPU \
    --database-version=$DATABASE_VERSION \
    --gce-zone=$GCE_ZONE \
    --memory=$MEMORY \
    --require-ssl \
    --storage-auto-increase \
    --storage-size=$STORAGE_SIZE \
    --account=$ACCOUNT \
    --project=$PROJECT
fi

### Create the airflow cluster. 
### The default node pool will be used only for the web server and scheduler, 
### This is set to be pre-emptible to lower costs
### https://cloud.google.com/sdk/gcloud/reference/container/clusters/create
if [ $HIGHLY_AVAILABLE = "FALSE" ] 
then
gcloud container clusters create $CLUSTER_NAME \
    --cluster-version=$CLUSTER_VERSION \
    --enable-autorepair \
    --enable-autoupgrade \
    --enable-legacy-authorization \
    --image-type=$IMAGE_TYPE \
    --enable-ip-alias \
    --labels=$KUBERNETES_MACHINE_LABELS \
    --machine-type=$MACHINE_TYPE \
    --preemptible \
    --node-labels=$AIRFLOW_MASTER_KUBERNETES_NODE_LABELS \
    --node-taints=$WORKER_POOL_NODE_TAINTS \
    --node-version=$CLUSTER_VERSION \
    --num-nodes=$LEADER_POOL_NUM_NODES \
    --zone=$GCE_ZONE \
    --node-locations=$GCE_ZONE \
    --scopes=$SCOPES \
    --account=$ACCOUNT \
    --project=$PROJECT
else
gcloud container clusters create $CLUSTER_NAME \
    --cluster-version=$CLUSTER_VERSION \
    --enable-autorepair \
    --enable-autoupgrade \
    --enable-legacy-authorization \
    --image-type=$IMAGE_TYPE \
    --enable-ip-alias \
    --labels=$KUBERNETES_MACHINE_LABELS \
    --machine-type=$MACHINE_TYPE \
    --preemptible \
    --node-labels=$AIRFLOW_MASTER_KUBERNETES_NODE_LABELS \
    --node-taints=$WORKER_POOL_NODE_TAINTS \
    --node-version=$CLUSTER_VERSION \
    --num-nodes=$LEADER_POOL_NUM_NODES \
    --region=$REGION \
    --scopes=$SCOPES \
    --account=$ACCOUNT \
    --project=$PROJECT
fi

### Create the worker node pool. This is pre-emptible so ensure that your DAGs are idempotent. 
### If they are not, then remove the pre-emptible flag. 
### The benefit of pre-emptible pods is that they are 80% off the spot price.
### Further scheduler fine tuning can be done, if you intend to use the KubernetesPodOperator
### If using the KubernetesPodOperator, you can create a new pool, and use affinities in the Pod Spec
### to schedule against.
if [ $CREATE_WORKER_POOL = "TRUE" ]
then
  if [ $HIGHLY_AVAILABLE = "FALSE" ]
  then
    gcloud container node-pools create $WORKER_NODE_POOL_NAME \
        --cluster=$CLUSTER_NAME \
        --enable-autorepair \
        --enable-autoupgrade \
        --image-type=$IMAGE_TYPE \
        --machine-type=$WORKER_NODE_MACHINE_TYPE \
        --node-labels=$WORKER_KUBERNETES_NODE_LABELS \
        --node-taints=$WORKER_POOL_NODE_TAINTS \
        --node-version=$CLUSTER_VERSION \
        --num-nodes=$WORKER_POOL_NUM_NODES \
        --enable-autoscaling \
        --preemptible \
        --max-nodes=$WORKER_POOL_MAX_NODES \
        --min-nodes=$WORKER_POOL_MIN_NODES \
        --zone=$GCE_ZONE \
        --scopes=$SCOPES \
        --account=$ACCOUNT \
        --project=$PROJECT
  else
    gcloud container node-pools create $WORKER_NODE_POOL_NAME \
        --cluster=$CLUSTER_NAME \
        --enable-autorepair \
        --enable-autoupgrade \
        --image-type=$IMAGE_TYPE \
        --machine-type=$WORKER_NODE_MACHINE_TYPE \
        --node-labels=$WORKER_KUBERNETES_NODE_LABELS \
        --node-taints=$WORKER_POOL_NODE_TAINTS \
        --node-version=$CLUSTER_VERSION \
        --num-nodes=$WORKER_POOL_NUM_NODES \
        --enable-autoscaling \
        --preemptible \
        --max-nodes=$WORKER_POOL_MAX_NODES \
        --min-nodes=$WORKER_POOL_MIN_NODES \
        --region=$REGION \
        --scopes=$SCOPES \
        --account=$ACCOUNT \
        --project=$PROJECT
  fi
fi

### Create service account for cloudsql-proxy to connect to and create kubernetes secret 
### https://cloud.google.com/sdk/gcloud/reference/iam/service-accounts/create
gcloud iam service-accounts create $CLOUDSQL_SERVICE_ACCOUNT \
    --display-name $CLOUDSQL_SERVICE_ACCOUNT \
    --account=$ACCOUNT \
    --project=$PROJECT

### Add the iam policy binding
### https://cloud.google.com/sdk/gcloud/reference/projects/add-iam-policy-binding
gcloud projects add-iam-policy-binding $PROJECT \
    --member serviceAccount:$CLOUDSQL_SERVICE_ACCOUNT@$PROJECT.iam.gserviceaccount.com \
    --role $CLOUDSQL_ROLE

gcloud projects add-iam-policy-binding $PROJECT \
    --member serviceAccount:$CLOUDSQL_SERVICE_ACCOUNT@$PROJECT.iam.gserviceaccount.com \
    --role $STORAGE_ROLE

gcloud iam service-accounts keys create $PWD/$CLOUDSQL_SERVICE_ACCOUNT.json \
    --iam-account $CLOUDSQL_SERVICE_ACCOUNT@$PROJECT.iam.gserviceaccount.com


### Create kubeconfig secret needed for the Kubernetes Scheduler to launch pods for the kubernetes executor
### The Kubernetes executor (to my knowledge) uses the mounted RBAC account to 
### launch Kubernetes Pod Operator pods and so doesn't need to have the kubeconfig mounted

TEMP_KUBECONFIG_DIR=$PWD
export KUBECONFIG=$TEMP_KUBECONFIG_DIR/$KUBERNETES_KUBECONFIG_SECRET
gcloud config set container/use_client_certificate True
if [ $HIGHLY_AVAILABLE = "TRUE" ] 
then
  gcloud beta container clusters get-credentials $CLUSTER_NAME --region $REGION --project $PROJECT
else
  gcloud container clusters get-credentials $CLUSTER_NAME --zone $GCE_ZONE --project $PROJECT
fi

### Set the default postgres user password, create the airflow user name and password and create the airflow database ###

gcloud sql users set-password postgres \
    --host "ignore-this-only-for-mysql" \
    --instance $DATABASE_INSTANCE_NAME \
    --project $PROJECT \
    --password $AIRFLOW_DATABASE_POSTGRES_USER_PASSWORD

gcloud sql users create $AIRFLOW_DATABASE_USER \
    --instance=$DATABASE_INSTANCE_NAME \
    --project=$PROJECT \
    --password=$AIRFLOW_DATABASE_USER_PASSWORD

# If the airflow user already exists, use this to update the password to what was generated above and uncomment the sql users create above.
# gcloud sql users set-password $AIRFLOW_DATABASE_USER \
#     --host "ignore-this-only-for-mysql" \
#     --instance $DATABASE_INSTANCE_NAME \
#     --project $PROJECT \
#     --password $AIRFLOW_DATABASE_USER_PASSWORD

gcloud sql databases create $AIRFLOW_DATABASE_NAME \
    --instance=$DATABASE_INSTANCE_NAME \
    --project=$PROJECT

SQL_ALCHEMY_CONN=postgresql+psycopg2://$AIRFLOW_DATABASE_USER:$AIRFLOW_DATABASE_USER_PASSWORD@$KUBERNETES_POSTGRES_CLOUDSQLPROXY_SERVICE:$KUBERNETES_POSTGRES_CLOUDSQLPROXY_PORT/$AIRFLOW_DATABASE_NAME

# Creat the fernet key which is needed to decrypt database the database
FERNET_KEY=$(dd if=/dev/urandom bs=32 count=1 2>/dev/null | openssl base64)

# If you want to save the secret below for future reference
# You can add a --output jsonpath-file=airflow-secret.json to the end
# kubectl create secret generic --help
# The google logs storage bucket is added for convenience but is ignored in the chart if .Values.airflowCfg.remoteLogging isn't set to true

kubectl create secret generic airflow \
    --from-literal=fernet-key=$FERNET_KEY \
    --from-literal=airflow-postgres-instance=$PROJECT:$REGION:$DATABASE_INSTANCE_NAME:$AIRFLOW_DATABASE_NAME \
    --from-literal=sql_alchemy_conn=$SQL_ALCHEMY_CONN \
    --from-file=$CLOUDSQL_SERVICE_ACCOUNT.json=$CLOUDSQL_SERVICE_ACCOUNT.json \
    --from-file=kubeconfig=$KUBERNETES_KUBECONFIG_SECRET \
    --from-literal=gcs-log-folder=gs://$GOOGLE_LOG_STORAGE_BUCKET

## Install tiller RBAC for helm
# http://zero-to-jupyterhub.readthedocs.io/en/latest/setup-helm.html
kubectl --namespace kube-system create serviceaccount tiller
kubectl create clusterrolebinding tiller \
                --clusterrole cluster-admin \
                --serviceaccount=kube-system:tiller
helm init --service-account tiller

# Make the storage bucket
if [ $CREATE_GOOGLE_STORAGE_BUCKET = "TRUE" ]
then
gsutil mb -p $PROJECT -c regional -l $REGION gs://$GOOGLE_LOG_STORAGE_BUCKET/
fi

# Create the cloud filestore instance
if [ $CREATE_CLOUD_FILESTORE = "TRUE" ]
then
gcloud beta filestore instances create $CLOUD_FILESTORE_NAME \
    --location $CLOUD_FILESTORE_ZONE \
    --project=$PROJECT \
    --tier=$CLOUD_FILESTORE_TIER \
    --file-share=name=$CLOUD_FILESTORE_SHARE_NAME,capacity=$CLOUD_FILESTORE_CAPACITY \
    --network=name=$CLOUD_FILESTORE_NETWORK,reserved-ip-range=$CLOUD_FILESTORE_RESERVED_IP
fi

### Remove the cloudsql service account and the kubeconfig file. They are persisted in the 
### kubernetes secret if you need to retrieve it. Run 'kubedecode airflow default' to decode.
### https://github.com/mveritym/kubedecode
rm $CLOUDSQL_SERVICE_ACCOUNT.json 
rm $KUBERNETES_KUBECONFIG_SECRET