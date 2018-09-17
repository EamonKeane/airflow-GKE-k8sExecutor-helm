# To deploy on gke

```bash
export CLOUDSDK_CORE_ACCOUNT=$(gcloud config get-value core/account)
export CLOUDSDK_CORE_PROJECT=$(gcloud config get-value core/project)
export CLOUDSDK_COMPUTE_REGION=$(gcloud config get-value compute/region)
export CLOUDSDK_COMPUTE_ZONE=$(gcloud config get-value compute/zone)
export AIRFLOW_SERVICE_ACCOUNT=airflow-deploy-svc-account6
./deploy/gke/create-service-account.sh
# Make any desired change to the values at deploy/gke/infra-$CLOUDSDK_CORE_PROJECT-values.json
# Then proceed to making the cluster
docker-compose -f deploy/gke/docker-compose-gke.yml up
K8S_CLUSTER_NAME=$(jq -r .K8S_CLUSTER_NAME deploy/gke/infra-$CLOUDSDK_CORE_PROJECT-values.json)
gcloud container clusters get-credentials $K8S_CLUSTER_NAME
WEB_POD_NAME=$(kubectl get pods --namespace default -l "app=airflow,tier=web" -o jsonpath="{.items[0].metadata.name}")
kubectl port-forward $WEB_POD_NAME 8080:8080
```