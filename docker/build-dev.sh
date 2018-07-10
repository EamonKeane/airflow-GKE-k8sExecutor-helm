TAG=0.2-dev
IMAGE_REPO=quay.io/eamonkeane/airflow-k8s
docker build . -f Dockerfile-dev -t $IMAGE_REPO:$TAG
docker push $IMAGE_REPO:$TAG

