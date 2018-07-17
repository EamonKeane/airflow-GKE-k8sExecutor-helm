#!/usr/bin/env bash

ACCOUNT=$(gcloud config get-value core/account)
PROJECT=$(gcloud config get-value core/project)
REGION=$(gcloud config get-value compute/region)
GCE_ZONE=$(gcloud config get-value compute/zone)
DATABASE_INSTANCE_NAME=airflow

./tidying-up.sh --project=$PROJECT \
                --gce_zone=$GCE_ZONE \
                --region=$REGION \
                --database_instance_name=$DATABASE_INSTANCE_NAME
