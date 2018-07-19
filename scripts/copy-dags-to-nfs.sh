NAMESPACE=default
GIT_FOLDER_ROOT=/Users/Eamon/kubernetes
DAGS_FOLDER_LOCAL=airflow-GKE-k8sExecutor-helm/dags
DAGS_FOLDER_REMOTE=/usr/local/airflow/dags
export POD_NAME=$(kubectl get pods --namespace $NAMESPACE -l "app=airflow,tier=scheduler" -o jsonpath="{.items[0].metadata.name}")
kubectl cp $GIT_FOLDER_ROOT/$DAGS_FOLDER_LOCAL/ $NAMESPACE/$POD_NAME:$DAGS_FOLDER_REMOTE