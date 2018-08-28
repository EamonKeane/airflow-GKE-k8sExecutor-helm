#!/usr/bin/env bash
TAG=0.6-oracle
IMAGE_REPO=quay.io/eamonkeane/airflow-k8s
docker build . -f Dockerfile-oracle -t $IMAGE_REPO:$TAG
docker push $IMAGE_REPO:$TAG