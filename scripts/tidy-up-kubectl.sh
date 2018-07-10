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
kubectl apply -f secret.yaml


CLOUDSQL_SERVICE_ACCOUNT="airflowcloudsql"
SQL_ALCHEMY_CONN=
AIRFLOW_POSTGRES_INSTANCE=
FERNET_KEY=
GCS_LOG_FOLDER=
KUBECONFIG="kubeconfig"

kubectl create secret generic airflow \
    --from-literal=fernet-key=$FERNET_KEY \
    --from-literal=airflow-postgres-instance=$AIRFLOW_POSTGRES_INSTANCE \
    --from-literal=sql_alchemy_conn=$SQL_ALCHEMY_CONN \
    --from-file=airflowcloudsql.json=$CLOUDSQL_SERVICE_ACCOUNT.json \
    --from-file=kubeconfig=$KUBECONFIG \
    --from-literal=gcs-log-folder=$GCS_LOG_FOLDER

## To delete stuck pod:
k delete po $NAME --force --grace-period=0
k edit po $NAME 
# remove finalizer and foreground deletion lines
# https://github.com/kubernetes/kubernetes/issues/65936
#   finalizers:
#  - foregroundDeletion


