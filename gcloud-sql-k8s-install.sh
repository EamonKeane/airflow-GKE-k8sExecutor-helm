#!/usr/bin/env bash
# Requires the following dependencies:
# Gcloud (tested with following configuration):
    # Google Cloud SDK 207.0.0
    # beta 2018.06.22
    # core 2018.06.22
    # gsutil 4.32 (for creating storage bucket)
# Openssl (for password generation - tested with LibreSSL 2.2.7)
# Helm (tested with 2.9.1)
# Kubectl (Client Version: version.Info{Major:"1", Minor:"11", GitVersion:"v1.11.0", 
    # GitCommit:"91e7b4fd31fcd3d5f436da26c980becec37ceefe", GitTreeState:"clean", 
    # BuildDate:"2018-06-27T22:29:25Z", GoVersion:"go1.10.3", Compiler:"gc", 
    # Platform:"darwin/amd64"}
set -e

#### GLOBAL GCP VARIABLES ####
PROJECT=
ACCOUNT=
REGION=
GCE_ZONE=
DATABASE_INSTANCE_NAME=

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
    -gce_zone=*|--gce_zone=*)
    GCE_ZONE="${i#*=}"
    ;;
    -database_instance_name=*|--database_instance_name=*)
    DATABASE_INSTANCE_NAME="${i#*=}"
    ;;
esac
done


### Airflow Logs bucket. This must be a globally unique name, 
### so add some randomness such as myorg-airflow-1235
### https://cloud.google.com/storage/docs/quickstart-gsutil
GOOGLE_LOG_STORAGE_BUCKET=$PROJECT-airflow

### Persistent disk name (used for dags)
DAGS_DISK_NAME=airflow-dags
DAGS_DISK_SIZE=10GB
# gcloud compute disk-types list
DAGS_DISK_TYPE=pd-ssd

#### DATABASE OPTIONS ####
ACTIVATION_POLICY=always
AVAILABILITY_TYPE=zonal
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
MACHINE_TYPE="n1-standard-2"

# Airflow worker pool options
CREATE_WORKER_POOL=FALSE
WORKER_NODE_POOL_NAME="airflow-workers"
WORKER_KUBERNETES_NODE_LABELS="airflow=airflow_workers,pool=preemptible"
WORKER_NODE_MACHINE_TYPE="n1-standard-4"
WORKER_POOL_NUM_NODES=0
WORKER_POOL_MAX_NODES=6 
WORKER_POOL_MIN_NODES=0

# Some of the kubernetes options require use of beta features.
gcloud config set container/use_v1_api false


### Create the postgres database ###
### https://cloud.google.com/sdk/gcloud/reference/sql/instances/create
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

### Create the airflow cluster. 
### The default node pool will be used only for the web server and scheduler, 
### for this reason this pool is not set to pre-emptible. Auto-scaling is enabled
### with a max of one node (per region, so 3) and a min of 0. Depending on kubernetes scheduling
### if all webserver and scheduler pods end up on the same node, GKE might only run one node
### so there is a balance of cost versus availability. This can be modified by using pod affinities
### to ensure a spread of webserver and scheduler on nodes. Delete enable-atuoscaling and min/max nodes
### if you want to have three nodes at all times
### https://cloud.google.com/sdk/gcloud/reference/container/clusters/create
gcloud container clusters create $CLUSTER_NAME \
    --cluster-version=$CLUSTER_VERSION \
    --enable-autorepair \
    --enable-autoupgrade \
    --enable-legacy-authorization \
    --image-type=$IMAGE_TYPE \
    --labels=$KUBERNETES_MACHINE_LABELS \
    --machine-type=$MACHINE_TYPE \
    --node-labels=$AIRFLOW_MASTER_KUBERNETES_NODE_LABELS \
    --node-taints=$WORKER_POOL_NODE_TAINTS \
    --node-version=$CLUSTER_VERSION \
    --num-nodes=$LEADER_POOL_NUM_NODES \
    --zone=$GCE_ZONE \
    --node-locations=$GCE_ZONE \
    --scopes=$SCOPES \
    --account=$ACCOUNT \
    --project=$PROJECT

### Create the worker node pool. This is pre-emptible so ensure that your DAGs are idempotent. 
### If they are not, then remove the pre-emptible flag. 
### The benefit of pre-emptible pods is that they are 80% off the spot price.
### Further scheduler fine tuning can be done, if you intend to use the KubernetesPodOperator
### If using the KubernetesPodOperator, you can create a new pool, and use affinities in the Pod Spec
### to schedule against.
if [ $CREATE_WORKER_POOL = "TRUE" ]; then
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
    --preemptible \
    --enable-autoscaling \
    --max-nodes=$WORKER_POOL_MAX_NODES \
    --min-nodes=$WORKER_POOL_MIN_NODES \
    --zone=$GCE_ZONE \
    --scopes=$SCOPES \
    --account=$ACCOUNT \
    --project=$PROJECT
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
gcloud container clusters get-credentials $CLUSTER_NAME --zone $GCE_ZONE --project $PROJECT

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
# Requires pip install cryptography
FERNET_KEY=$(python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())")

# If you want to save the secret below for future reference
# You can add a --output jsonpath-file=airflow-secret.json to the end
# kubectl create secret generic --help

kubectl create secret generic airflow \
    --from-literal=fernet-key=$FERNET_KEY \
    --from-literal=airflow-postgres-instance=$PROJECT:$REGION:$DATABASE_INSTANCE_NAME:$AIRFLOW_DATABASE_NAME \
    --from-literal=sql_alchemy_conn=$SQL_ALCHEMY_CONN \
    --from-file=$CLOUDSQL_SERVICE_ACCOUNT.json=$CLOUDSQL_SERVICE_ACCOUNT.json \
    --from-file=kubeconfig=$KUBERNETES_KUBECONFIG_SECRET \
    --from-literal=gcs-log-folder=gs://$GOOGLE_LOG_STORAGE_BUCKET

## Install tiller RBAC for helm
kubectl apply -f kubernetes-yaml/
## Initialise Helm
helm init --service-account tiller

# Make the storage bucket
gsutil mb -p $PROJECT -c regional -l $REGION gs://$GOOGLE_LOG_STORAGE_BUCKET/

### Remove the cloudsql service account and the kubeconfig file. They are persisted in the 
### kubernetes secret if you need to retrieve it. Run 'kubedecode airflow default' to decode.
### https://github.com/mveritym/kubedecode
rm $CLOUDSQL_SERVICE_ACCOUNT.json 
rm $KUBERNETES_KUBECONFIG_SECRET

gcloud compute disks create $DAGS_DISK_NAME \
  --description="Used to sync github with dags" \
  --size=$DAGS_DISK_SIZE \
  --type=$DAGS_DISK_TYPE \
  --zone=$GCE_ZONE \
  --project=$PROJECT

