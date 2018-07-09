## Deploy an airflow kubernetes cluster with CloudSql and GKE in under 10 minutes

![airflow-gke-deployed](images/airflow-gke.png "Airflow GKE Helm")

Installation instructions:

```bash
git clone https://github.com/EamonKeane/airflow-GKE-k8sExecutor-helm.git
cd airflow-GKE-k8sExecutor-helm
```

```bash
ACCOUNT=username@somedomain.com
PROJECT="myorg-123456"
GCE_ZONE="europe-west2-c"
REGION="europe-west2"
./gcloud-sql-k8s-install.sh \
    --project=$PROJECT \
    --account=$ACCOUNT \
    --gce_zone=$GCE_ZONE \
    --region=$REGION
```

```bash
helm upgrade \
    --install \
    --set google.project=$PROJECT \
    --set google.region=$REGION \
    airflow \
    airflow
```

You can change airflow/airflow.cfg and re-run the above `helm upgrade --install` command to redeploy the changes. This takes approximately 30 seconds.

## To view the dashboard UI:

```bash
export POD_NAME=$(kubectl get pods --namespace default -l "app=airflow,tier=web" -o jsonpath="{.items[0].metadata.name}")
echo "Visit http://127.0.0.1:8080 to use your application"
kubectl port-forward $POD_NAME 8080:8080
```

To install an ingress with nginx-ingress use `--set ingress.enabled=true`. There is no authentication by default, so please add your authentication method to `airflow/airflow.cfg`.

## Tidying up
The easiest way to tidy-up is to delete the project and make a new one if re-deploying, however there are steps in tidying-up.sh to delete the individual resources.

## Input
This is a work in progress and the install script is a bit brittle. One area where I could use some input is the best way to set up storage for DAGS on GKE. Persistent disks can only be attached to one
node at a time (hence this example only works on one node). I see some options such as gcsfuse but am not sure if they would work with the k8s executor worker definitions. Cloud Filestore would work but this is not released yet (beta due soon apparently). https://github.com/kubernetes-sigs/gcp-filestore-csi-driver

## Helm chart layout
There are a few elements to the chart:
* This chart only focuses on the kubernetes executor and is tailored to run on GKE, but
with some effort could be modified to run on premise or EKS/AKS.
* A persistent disk is used for dags. You need to populate this separately using e.g. Jenkins.
* Pre-install hooks add the airflow-RBAC account, dags PV, dags PVC and CloudSQL service. If the step fails at this point, you will need to remove everything before running helm again. See `tidying-up.sh` for details.
* Pre-install and pre-upgrade hook to run the alembic migrations
* Separate, templated airflow.cfg a change of which triggers a redeployment of both the web scheduler and the web server. This is due to the name of the configmap being appended with the current seconds (-{{ .Release.Time.Seconds }}) so a new configmap gets deployed each time. You may want to delete old configmaps from time to time.
