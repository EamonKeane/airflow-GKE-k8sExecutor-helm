#!/usr/bin/env bash

# if you have a failed deployment, use this block to delete everything in the airlfow namespace
AIRFLOW_NAMESPACE=default
helm del --purge airflow
kubectl delete service/airflow-postgresql --namespace $AIRFLOW_NAMESPACE
kubectl delete deployment.apps/airflow-postgresql --force --grace-period=0 --namespace $AIRFLOW_NAMESPACE
kubectl delete serviceaccount airflow-rbac --namespace $AIRFLOW_NAMESPACE
kubectl delete clusterrolebinding airflow-clusterrolebinding --namespace $AIRFLOW_NAMESPACE
kubectl delete deployment.apps/airflow-scheduler --namespace $AIRFLOW_NAMESPACE
kubectl delete deployment.apps/airflow-web --namespace $AIRFLOW_NAMESPACE
kubectl delete service/airflow --namespace $AIRFLOW_NAMESPACE
kubectl delete job --all --namespace $AIRFLOW_NAMESPACE
# kubectl delete cm --all --namespace $AIRFLOW_NAMESPACE
kubectl delete pvc airflow-dags --namespace $AIRFLOW_NAMESPACE
kubectl delete pvc airflow-logs --namespace $AIRFLOW_NAMESPACE
kubectl delete pv airflow-logs --namespace $AIRFLOW_NAMESPACE
kubectl delete pv airflow-dags --namespace $AIRFLOW_NAMESPACE
kubectl delete sc azurefile-airflow --namespace $AIRFLOW_NAMESPACE
kubectl delete clusterroles system:azure-cloud-provider --namespace $AIRFLOW_NAMESPACE
kubectl delete clusterrolebinding system:azure-cloud-provider --namespace $AIRFLOW_NAMESPACE
kubectl delete deploy nfs-server
kubectl delete deploy nfs-svc
#####

## To delete stuck pod:
kubectl delete po $NAME --force --grace-period=0
kubectl edit po $NAME 
# remove finalizer and foreground deletion lines
# https://github.com/kubernetes/kubernetes/issues/65936
#   finalizers:
#  - foregroundDeletion
