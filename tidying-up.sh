#!/usr/bin/env bash

# set -e

#### GLOBAL GCP VARIABLES ####
PROJECT=
REGION=
GCE_ZONE=


CLUSTER_NAME="airflow"

DATABASE_INSTANCE_NAME="airflow"

DAGS_DISK_NAME="airflow-dags"

SERVICE_ACCOUNT_NAME=airflowcloudsql
CLOUDSQL_ROLE='roles/cloudsql.admin'
STORAGE_ROLE='roles/storage.admin'

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

gcloud compute disks delete $DAGS_DISK_NAME --project=$PROJECT --zone=$GCE_ZONE --quiet

### Permission denied, so had to do this in the dashboard
gcloud iam service-accounts remove-iam-policy-binding $SERVICE_ACCOUNT_FULL \
    --project=$PROJECT \
    --member=serviceAccount:$SERVICE_ACCOUNT_FULL \
    --role=$CLOUDSQL_ROLE --quiet

gcloud iam service-accounts remove-iam-policy-binding $SERVICE_ACCOUNT_FULL \
    --project=$PROJECT \
    --member=serviceAccount:$SERVICE_ACCOUNT_FULL \
    --role=$STORAGE_ROLE --quiet


