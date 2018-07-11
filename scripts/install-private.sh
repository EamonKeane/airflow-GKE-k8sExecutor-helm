ACCOUNT=eamon@logistio.ie
PROJECT="icabbi-202810"
GCE_ZONE="europe-west2-a"
REGION="europe-west2"
DATABASE_INSTANCE_NAME=airflow
./gcloud-sql-k8s-install.sh \
    --project=$PROJECT \
    --account=$ACCOUNT \
    --gce_zone=$GCE_ZONE \
    --region=$REGION \
    --database_instance_name=$DATABASE_INSTANCE_NAME