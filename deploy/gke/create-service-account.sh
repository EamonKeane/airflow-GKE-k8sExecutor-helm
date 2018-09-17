#! /usr/bin/env bash
set -Eeuxo pipefail 

jq ".CLOUDSDK_CORE_PROJECT = \"$CLOUDSDK_CORE_PROJECT\"" deploy/gke/infra-template-values.json \
        > tmp.json && mv tmp.json deploy/gke/infra-$CLOUDSDK_CORE_PROJECT-values.json
jq ".CLOUDSDK_COMPUTE_REGION = \"$CLOUDSDK_COMPUTE_REGION\"" deploy/gke/infra-$CLOUDSDK_CORE_PROJECT-values.json \
            > tmp.json && mv tmp.json deploy/gke/infra-$CLOUDSDK_CORE_PROJECT-values.json
jq ".CLOUDSDK_COMPUTE_ZONE = \"$CLOUDSDK_COMPUTE_ZONE\"" deploy/gke/infra-$CLOUDSDK_CORE_PROJECT-values.json \
            > tmp.json && mv tmp.json deploy/gke/infra-$CLOUDSDK_CORE_PROJECT-values.json

gcloud iam service-accounts create $AIRFLOW_SERVICE_ACCOUNT \
    --display-name $AIRFLOW_SERVICE_ACCOUNT

### Add the iam policy binding
### https://cloud.google.com/sdk/gcloud/reference/projects/add-iam-policy-binding
gcloud projects add-iam-policy-binding $CLOUDSDK_CORE_PROJECT \
    --member serviceAccount:$AIRFLOW_SERVICE_ACCOUNT@$CLOUDSDK_CORE_PROJECT.iam.gserviceaccount.com \
    --role 'roles/owner'

### Store the service account in the root secrets folder
gcloud iam service-accounts keys create \
    secrets/$AIRFLOW_SERVICE_ACCOUNT.json \
    --iam-account \
    $AIRFLOW_SERVICE_ACCOUNT@$CLOUDSDK_CORE_PROJECT.iam.gserviceaccount.com