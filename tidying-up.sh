#!/usr/bin/env bash

# set -e

#### GLOBAL GCP VARIABLES ####
ACCOUNT=$(gcloud config get-value core/account)
PROJECT=$(gcloud config get-value core/project)
REGION=$(gcloud config get-value compute/region)
GCE_ZONE=$(gcloud config get-value compute/zone)

CLUSTER_NAME="airflow"

DATABASE_INSTANCE_NAME="airflow"

SERVICE_ACCOUNT_NAME=airflowcloudsql
CLOUDSQL_ROLE='roles/cloudsql.admin'
STORAGE_ROLE='roles/storage.admin'

NFS_DEPLOYMENT_NAME=dags-airflow

CLOUD_FILESTORE_INSTANCE=airflow
CLOUD_FILESTORE_LOCATION=europe-west1-b
PROJECT=icabbi-test-210421

for i in "$@"
do
case ${i} in
    -project=*|--project=*)
    PROJECT="${i#*=}"
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

GCE_LOG_BUCKET_NAME=$PROJECT-airflow

SERVICE_ACCOUNT_FULL=$SERVICE_ACCOUNT_NAME@$PROJECT.iam.gserviceaccount.com

gcloud sql instances delete $DATABASE_INSTANCE_NAME --project=$PROJECT --async --quiet

gcloud container clusters delete $CLUSTER_NAME --project=$PROJECT --zone=$GCE_ZONE --async --quiet

gcloud iam service-accounts delete $SERVICE_ACCOUNT_NAME@$PROJECT.iam.gserviceaccount.com --quiet

gsutil rm -r gs://$PROJECT-airflow

gcloud beta filestore instances delete $CLOUD_FILESTORE_INSTANCE \
                                    --location=$CLOUD_FILESTORE_LOCATION \
                                    --project=$PROJECT

### Permission denied, so had to do this in the dashboard
gcloud iam service-accounts remove-iam-policy-binding $SERVICE_ACCOUNT_FULL \
    --project=$PROJECT \
    --member=serviceAccount:$SERVICE_ACCOUNT_FULL \
    --role=$CLOUDSQL_ROLE --quiet

gcloud iam service-accounts remove-iam-policy-binding $SERVICE_ACCOUNT_FULL \
    --project=$PROJECT \
    --member=serviceAccount:$SERVICE_ACCOUNT_FULL \
    --role=$STORAGE_ROLE --quiet

gcloud deployment-manager deployments delete $NFS_DEPLOYMENT_NAME
