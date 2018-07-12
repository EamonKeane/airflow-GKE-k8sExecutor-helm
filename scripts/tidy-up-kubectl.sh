#!/usr/bin/env bash

# if you have a failed deployment, use this to delete everything
helm del --purge airflow
kubectl delete service/airflow-postgresql
kubectl delete deployment.apps/airflow-postgresql --force --grace-period=0
kubectl delete serviceaccount airflow-rbac
kubectl delete clusterrolebinding airflow-clusterrolebinding
kubectl delete deployment.apps/airflow-scheduler
kubectl delete deployment.apps/airflow-web
kubectl delete service/airflow
kubectl delete job --all
kubectl delete cm --all
kubectl delete pvc --all
kubectl delete pv --all

kubectl delete secret airflow

## To delete stuck pod:
kubectl delete po $NAME --force --grace-period=0
kubectl edit po $NAME 
# remove finalizer and foreground deletion lines
# https://github.com/kubernetes/kubernetes/issues/65936
#   finalizers:
#  - foregroundDeletion

