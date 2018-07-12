ACCOUNT=eamon@logistio.ie
PROJECT="icabbi-202810"
GCE_ZONE="europe-west2-a"
REGION="europe-west2"

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
