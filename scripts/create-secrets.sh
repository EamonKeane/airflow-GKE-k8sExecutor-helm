
#!/usr/bin/env bash

# Create the general secret for the airflow chart
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


# If using google oauth, create this secret

CLIENT_ID=
CLIENT_SECRET=

kubectl create secret generic google-oauth \
  --from-literal=client_id=$CLIENT_ID \
  --from-literal=client_secret=$CLIENT_SECRET
