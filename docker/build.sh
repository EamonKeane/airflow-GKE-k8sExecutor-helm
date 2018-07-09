TAG=0.2
IMAGE_REPO=quay.io/eamonkeane/airflow-k8s
docker build . -f Dockerfile -t $IMAGE_REPO:$TAG
docker push $IMAGE_REPO:$TAG