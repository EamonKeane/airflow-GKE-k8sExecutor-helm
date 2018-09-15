# To deploy on gke

```bash
SETUP_DIR=deploy/gke
cd $SETUP_DIR
export AIRFLOW_SERVICE_ACCOUNT=airflow-deploy-svc-account
export CLOUDSDK_CORE_ACCOUNT=$(gcloud config get-value core/account)
export CLOUDSDK_CORE_PROJECT=$(gcloud config get-value core/project)
export CLOUDSDK_COMPUTE_REGION=$(gcloud config get-value compute/region)
export CLOUDSDK_COMPUTE_ZONE=$(gcloud config get-value compute/zone)

jq ".CLOUDSDK_CORE_PROJECT = \"$CLOUDSDK_CORE_PROJECT\"" infra-template-values.json > tmp.json && mv tmp.json infra-$CLOUDSDK_CORE_PROJECT-values.json
jq ".CLOUDSDK_COMPUTE_REGION = \"$CLOUDSDK_COMPUTE_REGION\"" infra-$CLOUDSDK_CORE_PROJECT-values.json > tmp.json && mv tmp.json infra-$CLOUDSDK_CORE_PROJECT-values.json
jq ".CLOUDSDK_COMPUTE_ZONE = \"$CLOUDSDK_COMPUTE_ZONE\"" infra-$CLOUDSDK_CORE_PROJECT-values.json > tmp.json && mv tmp.json infra-$CLOUDSDK_CORE_PROJECT-values.json

gcloud iam service-accounts create $AIRFLOW_SERVICE_ACCOUNT \
    --display-name $AIRFLOW_SERVICE_ACCOUNT

### Add the iam policy binding
### https://cloud.google.com/sdk/gcloud/reference/projects/add-iam-policy-binding
gcloud projects add-iam-policy-binding $CLOUDSDK_CORE_PROJECT \
    --member serviceAccount:$AIRFLOW_SERVICE_ACCOUNT@$CLOUDSDK_CORE_PROJECT.iam.gserviceaccount.com \
    --role 'roles/owner'

### Store the service account in the root secrets folder
gcloud iam service-accounts keys create \
    ../../secrets/$AIRFLOW_SERVICE_ACCOUNT.json \
    --iam-account \
    $AIRFLOW_SERVICE_ACCOUNT@$CLOUDSDK_CORE_PROJECT.iam.gserviceaccount.com
```

```bash
docker-compose -f docker-compose-gke.yml up --build --force-recreate
```