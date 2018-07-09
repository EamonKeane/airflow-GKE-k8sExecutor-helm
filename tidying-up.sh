PROJECT=icabbi-202810
ACCOUNT=eamon@logistio.ie
GCE_ZONE="europe-west2-c"

GCE_LOG_BUCKET_NAME=

CLUSTER_NAME="icabbi-airflow"

DATABASE_INSTANCE_NAME="icabbi-airflow21"

DAGS_DISK_NAME="airflow-dags"

SERVICE_ACCOUNT_NAME=airflowcloudsql
CLOUDSQL_ROLE='roles/cloudsql.admin'
STORAGE_ROLE='roles/storage.admin'
SERVICE_ACCOUNT_FULL=$SERVICE_ACCOUNT_NAME@$PROJECT.iam.gserviceaccount.com

gcloud sql instances delete $DATABASE_INSTANCE_NAME --project=$PROJECT

gcloud container clusters delete $CLUSTER_NAME --project=$PROJECT --zone=$GCE_ZONE

gcloud iam service-accounts delete $SERVICE_ACCOUNT_NAME@$PROJECT.iam.gserviceaccount.com

### Permission denied, so had to do this in the dashboard
gcloud iam service-accounts remove-iam-policy-binding $SERVICE_ACCOUNT_FULL \
    --project=$PROJECT \
    --member=serviceAccount:$SERVICE_ACCOUNT_FULL \
    --role=$CLOUDSQL_ROLE

gcloud iam service-accounts remove-iam-policy-binding $SERVICE_ACCOUNT_FULL \
    --project=$PROJECT \
    --member=serviceAccount:$SERVICE_ACCOUNT_FULL \
    --role=$STORAGE_ROLE

gsutil rm -r gs://$PROJECT-airflow

gcloud compute disks delete $DAGS_DISK_NAME --project=$PROJECT


# if you have a failed deployment, use this to delete everything
helm del --purge airflow
kubectl delete service/airflow-postgresql
kubectl delete deployment.apps/airflow-postgresql
kubectl delete serviceaccount airflow-rbac
kubectl delete clusterrolebinding airflow-clusterrolebinding
kubectl delete deployment.apps/airflow-scheduler
kubectl delete deployment.apps/airflow-web
kubectl delete service/airflow
kubectl delete job --all
kubectl delete cm --all
kubectl delete pvc --all
kubectl delete pv --all