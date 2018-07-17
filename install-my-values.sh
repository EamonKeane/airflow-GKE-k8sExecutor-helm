#!/usr/bin/env bash

ACCOUNT=$(gcloud config get-value core/account)
PROJECT=$(gcloud config get-value core/project)
REGION=$(gcloud config get-value compute/region)
GCE_ZONE=$(gcloud config get-value compute/zone)
DATABASE_INSTANCE_NAME=airflow

ACCOUNT=$(gcloud config get-value core/account)
PROJECT=icabbi-test-210421
REGION=$(gcloud config get-value compute/region)
GCE_ZONE=$(gcloud config get-value compute/zone)

TAG=0.3

databaseInstance=airflow2

helm upgrade \
    --install \
    --wait \
    --set google.project=$PROJECT \
    --set google.region=$REGION \
    --set google.databaseInstance=$databaseInstance \
    --set webScheduler.tag=$TAG \
    --set airflowCfg.kubernetes.workerContainerTag=$TAG \
    --values my-values.yaml \
    airflow \
    airflow
