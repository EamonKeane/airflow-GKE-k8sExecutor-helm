
# Airflow kubernetes executor

This repo contains scripts to deploy an airflow-ready cluster (with required secrets and persistent volumes) on GKE, AKS and docker-for-mac. A helm chart is then used to install the k8s-executor and copy over example dags. If you need support for other executors, check out the following chart.

`https://github.com/helm/charts/issues/2591`
`https://github.com/gsemet/charts/tree/airflow/incubator/airflow`

## 5 minute GKE install

The only requirement for the following installation is to have `docker-compose`, `google cloud sdk`  and `jq` installed (the version is not important). Run all the commands below in the same shell at the root of this repo.

```bash
export CLOUDSDK_CORE_ACCOUNT=$(gcloud config get-value core/account)
export CLOUDSDK_CORE_PROJECT=$(gcloud config get-value core/project)
export CLOUDSDK_COMPUTE_REGION=$(gcloud config get-value compute/region)
export CLOUDSDK_COMPUTE_ZONE=$(gcloud config get-value compute/zone)
export AIRFLOW_SERVICE_ACCOUNT=airflow-deploy-svc-account
```

The following script creates a service account used by the sdk in the docker pod and also creates a values file (from the template at `deploy/gke/infra-template-values.json`) for choosing infrastructure parameters (e.g. Cloudsql DB size and k8s cluster size).

```bash
./deploy/gke/create-service-account.sh
```

Make any desired change to the values at `deploy/gke/infra-$CLOUDSDK_CORE_PROJECT-values.json`
Then proceed to making the cluster.

The cluster-install script used by docker-compose does the following:

* Creates a postgres `Cloudsql` database instance and airflow database
* Creates a `1 node`, `4vCPU`, `GKE` cluster (installs on free account)
* Creates a `FERNET_KEY` and `SQL_ALCHEMY_CONN` k8s secret for airflow (also saved in secrets/airflow)
* Creates an `NFS` disk on `GCP` to allow for mounting by multiple airflow pods
* Installs airflow with helm (this contains an `NFS` server)
* Copies the `dags` folder to the `NFS` server

```bash
docker-compose -f deploy/gke/docker-compose-gke.yml up
```

When the install has completed, run the commands below to view the web UI.

```bash
K8S_CLUSTER_NAME=$(jq -r .K8S_CLUSTER_NAME deploy/gke/infra-$CLOUDSDK_CORE_PROJECT-values.json)
gcloud container clusters get-credentials $K8S_CLUSTER_NAME
WEB_POD_NAME=$(kubectl get pods --namespace default -l "app=airflow,tier=web" -o jsonpath="{.items[0].metadata.name}")
kubectl port-forward $WEB_POD_NAME 8080:8080
```

Make any changes desired to the airflow helm chart and redeply using:

```bash
helm upgrade \
    --install \
    --wait \
    airflow \
    airflow
```

If any changes are made to the dag, quickly copy the example dags folder here to the NFS by using `kubectl cp`:

```bash
NAMESPACE=default
GIT_FOLDER_ROOT=/Users/Eamon/kubernetes
DAGS_FOLDER_LOCAL=airflow-GKE-k8sExecutor-helm/dags
DAGS_FOLDER_REMOTE=/usr/local/airflow/dags
export POD_NAME=$(kubectl get pods --namespace $NAMESPACE -l "app=airflow,tier=scheduler" -o jsonpath="{.items[0].metadata.name}")
kubectl cp $GIT_FOLDER_ROOT/$DAGS_FOLDER_LOCAL/ $NAMESPACE/$POD_NAME:$DAGS_FOLDER_REMOTE
```

Alternatively run the script below:

```bash
./scripts/copy-dags-to-nfs.sh
```

View the dashboard using the instructions below and you should see the examples in the dags folder of this repo.

```bash
export POD_NAME=$(kubectl get pods --namespace default -l "app=airflow,tier=web" -o jsonpath="{.items[0].metadata.name}")
echo "Visit http://127.0.0.1:8080 to use your application"
kubectl port-forward $POD_NAME 8080:8080
```

To expose the web server behind a https url with google oauth, set `webScheduler.web.authenticate` to `True` and see the section for google-oauth, cert-manager and nginx-ingress install instructions [SSL UI](#Exposing-oauth2-Google-ingress-with-cert-manager-and-nginx-ingress).

## Tidying up

The easiest way to tidy-up is to delete the project and make a new one if re-deploying, however there are steps in `tidying-up.sh` to delete the individual resources.
For azure you can simply `az group delete --resource-group $RESOURCE_GROUP` to delete everything.

## Helm chart layout

There are a few elements to the chart:

* This chart only focuses on the kubernetes executor and is tailored to run on GKE, but with some effort could be modified to run on premise or EKS/AKS.
* Google Cloud Filestore (beta - equivalent of EFS and AFS on AWS and Azure respectively). You need to populate this separately using e.g. Jenkins (see sample jenkins file and instructions below [Jenkins](#Setup-Jenkins-to-sync-dags)).
* Pre-install hooks add the airflow-RBAC account, dags/logs PV, dags/logs PVC and CloudSQL service. If the step fails at this point, you will need to remove everything before running helm again. See `tidying-up.sh` for details.
* Pre-install and pre-upgrade hook to run the alembic migrations
* Separate, templated airflow.cfg a change of which triggers a redeployment of both the web scheduler and the web server. This is due to the name of the configmap being appended with the current seconds (-{{ .Release.Time.Seconds }}) so a new configmap gets deployed each time. You may want to delete old configmaps from time to time.

## Debugging

When debugging it is useful to set the executor to LocalExecutor. This can be done by the following:

```bash
--set airflowCfg.core.executor=LocalExecutor
```

If the installation is giving you trouble, running a pod inside the cluster can be helpful. This can be done e.g. by:

```bash
kubectl run airflow-test --rm -it --image quay.io/eamonkeane/airflow-k8s:0.5-oracle --command /bin/bash
```

This way you can see all the logs on one pod and can still test kubernetes using the Pod Operator (this requires a kubeconfig to be mounted on the scheduler pod, which is part of the setup).

To view the applied configuration, shell into a pod and paste the following code:

```python
python
from airflow.configuration import *
from pprint import pprint
pprint(conf.as_dict(display_source=True,display_sensitive=True))
```

## Exposing oauth2 Google ingress with cert-manager and nginx-ingress

```bash
helm install stable/cert-manager \
    --name cert-manager \
    --namespace kube-system \
    --set ingressShim.defaultIssuerName=letsencrypt-prod \
    --set ingressShim.defaultIssuerKind=ClusterIssuer
```

Add the default cluster issuer (this will install an let's encrypt cert using the below letsencrypt-prod certificate issuer for all). Replace the email field with your email.

```bash
cat <<EOF | kubectl create -f -
apiVersion: certmanager.k8s.io/v1alpha1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: mydomain@logistio.ie
    privateKeySecretRef:
      name: letsencrypt-prod
    http01: {}
EOF
```

Install nginx-ingress with the option to preserve sticky sessions (externalTrafficPolicy). This will take around a minute to install.

```bash
helm install stable/nginx-ingress \
    --wait \
    --name nginx-ingress \
    --namespace kube-system \
    --set rbac.create=true \
    --set controller.service.externalTrafficPolicy=Local
```

```bash
INGRESS_IP=$(kubectl get svc \
            --namespace kube-system \
            --selector=app=nginx-ingress,component=controller \
            -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}');echo ${INGRESS_IP}
```

Add a DNS A record of `$MY_AIRFLOW_DOMAIN` with IP address `$INGRESS_IP` with your domain name provider. Verify that it has updated.

```bash
dig $MY_AIRFLOW_DOMAIN
...
;; ANSWER SECTION:
airflow.mysite.io. 5      IN      A       35.230.155.177
...
```

Create a file called `my-values.yaml` using `my-values.example.yaml` template and populate it with the values below.

```bash
MY_AIRFLOW_DOMAIN=airflow.mysite.io
```

```yaml
ingress:
  enabled: true
  hosts:
    - $MY_DOMAIN
  tls:
  - hosts:
    - $MY_DOMAIN
    secretName: $MY_DOMAIN
```

Create an oauth2 credential on Google Cloud Dashboard.

```bash
PROJECT=myorg-123456
OAUTH_APP_NAME=myorg-airflow
```

* Navigate to <https://console.cloud.google.com/apis/credentials?project=$PROJECT>
* Click Create Credentials
* Select OAuth Client ID
* Select Web Application
* Enter `$OAUTH_APP_NAME` as the Name
* In authorized redirect URLs, enter <https://$MY_DOMAIN/oauth2callback>
* Click download json at the top of the page

Get the file path of the json file:

```bash
MY_OAUTH2_CREDENTIALS=...client_secret_123456778910-oul980h2fk7om2o67aj5d0aum79pqv8a.apps.googleusercontent.com.json
```

Create a kubernetes secret to hold the client_id and client_secret (these will be set as env variables in the web pod)

```bash
CLIENT_ID=$(jq .web.client_id $MY_OAUTH2_CREDENTIALS --raw-output )
CLIENT_SECRET=$(jq .web.client_secret $MY_OAUTH2_CREDENTIALS --raw-output )
kubectl create secret generic google-oauth \
        --from-literal=client_id=$CLIENT_ID \
        --from-literal=client_secret=$CLIENT_SECRET
```

Add the below values to `my-values.yaml`:

```yaml
webScheduler:
  web:
    authenticate: True
    authBackend: airflow.contrib.auth.backends.google_auth
    googleAuthDomain: mysite.io
    googleAuthSecret: google-oauth
    googleAuthSecretClientIDKey: client_id
    googleAuthSecretClientSecretKey: client_secret
```

Update the helm deployment.

```bash
helm upgrade \
    --install \
    --set google.project=$PROJECT \
    --set google.region=$REGION \
    --values my-values.yaml \
    airflow \
    airflow
```

Navigate to `https://$MY_AIRFLOW_DOMAIN`. Log into google, you should now see the dashboard UI.


## Setup Jenkins to sync dags

```bash
jq ".nfs.name = \"$AIRFLOW_NFS_VM_NAME\"" Jenkinsfile.json > tmp.json && mv tmp.json Jenkinsfile.json
jq ".nfs.internalIP = \"$INTERNAL_IP\"" Jenkinsfile.json > tmp.json && mv tmp.json Jenkinsfile.json
jq ".nfs.dagFolder = \"$STORAGE_NAME\"" Jenkinsfile.json > tmp.json && mv tmp.json Jenkinsfile.json
jq ".nfs.zone = \"$GCE_ZONE\"" Jenkinsfile.json > tmp.json && mv tmp.json Jenkinsfile.json
```

In the Jenkinsfile pod template, replace `nfsVolume` variables to the following:

```bash
serverAddress: $INTERNAL_IP
serverPath: $STORAGE_NAME
```

Set up Jenkins to trigger a build on each git push of this repository (see here for example instructions: <https://github.com/eamonkeane/jenkins-blue>). The dags folder will then appear synced in your webscheduler pods.  

## NFS Server

```bash
NFS_DEPLOYMENT_NAME=airflow
NFS_ZONE=$GCE_ZONE
NFS_INSTANCE_NAME=myorg-airflow
STORAGE_NAME=airflow
```

* Navigate to: <https://console.cloud.google.com/launcher/details/click-to-deploy-images/singlefs?q=nfs&project=$PROJECT>
* Click `LAUNCH ON COMPUTE ENGINE`
* Enter `NFS_DEPLOYMENT` name as the deployment name
* Enter `NFS_ZONE`  as the zone
* Change the machine type to 1vCPU (this is sufficient)
* Enter instance name as $INSTANCE_NAME
* Leave the nfs folder as data unless you want to change it
* Change the disk to SSD
* Change the storage disk size to 10GB (or more if you have a lot of dags)
* Change the filesystem to ext4
* Click deploy

Update your `my-values.yaml` with the below block:

Get the internal IP address of your instance:

```bash
AIRFLOW_NFS_VM_NAME=$NFS_DEPLOYMENT_NAME-vm

INTERNAL_IP=$(gcloud compute instances describe $AIRFLOW_NFS_VM_NAME \
                --zone=$NFS_ZONE \
                --format='value(networkInterfaces[0].networkIP)')
```

```yaml
dagVolume:
  nfsServer: "$INTERNAL_IP"
  nfsPath: "/$STORAGE_NAME"
```

Setup jenkins per the instructions [below](#Setup-Jenkins-to-sync-dags), or alternatively, copy the example pod operator in this repo to the $STORAGE_NAME of the NFS server (you can get connection instructions at this url <https://console.cloud.google.com/dm/deployments/details/$NFS_DEPLOYMENT_NAME?project=$PROJECT>)

## Monitoring and Logging

For effortless (and free) monitoring and logging, use the Google Click to Deploy to GKE apps. This will trigger the autoscaling worker pool to scale up to meet the demands. The only cost is the additional persistent disks and the nodes (approximately two `n1-highcpu-4` nodes).

### Elasticsearch

* Follow the (very simple) instructions at:

<https://marketplace.gcr.io/google/elastic-gke-logging>

To view airflow logs substitute the `namespace` and `app instance name` what you entered on the previous page:

```bash
ELASTICSEARCH_APP_INSTANCE_NAME=elastic-gke-logging-1-kibana-svc
ELASTICSEARCH_DEPLOYMENT_NAMESPACE=cluster-monitoring
KIBANA_PORT=5601
```

* Open a webpage:

```bash
kubectl port-forward $ELASTICSEARCH_APP_INSTANCE_NAME svc/ -n $ELASTICSEARCH_DEPLOYMENT_NAMESPACE $KIBANA_PORT
open http://localhost:$KIBANA_PORT/
```

* Select `OPEN` at the top of the page
* Select `GKE Apps Logs`
* You will then see something similar to the below (this is because of the annotation `app.kubernetes.io/name: airflow` added to each of the deployment objects (<https://kubernetes.io/docs/concepts/overview/working-with-objects/common-labels/>).

![airflow-elasticsearch](images/airflow-elasticsearch.png "Airflow Elasticsearch Logs")

### Prometheus and Grafana

* Follow the (very simple) instructions at:

https://marketplace.gcr.io/google/prometheus

To view the grafana dashboard:

```bash
GRAF_PROM_APP_INSTANCE_NAME=prometheus-1
GRAF_PROM_DEPLOYMENT_NAMESPACE=cluster-monitoring
GRAFANA_PORT=3000
```

* Open a webpage:

```bash
kubectl port-forward --namespace $GRAF_PROM_DEPLOYMENT_NAMESPACE $GRAF_PROM_APP_INSTANCE_NAME $GRAFANA_PORT
open http://localhost:$GRAFANA_PORT/
```

* Enter the following username and password:

```bash
USERNAME=admin
PASSWORD=

kubectl get secret $GRAF_PROM_APP_INSTANCE_NAME-grafana \
                   --namespace=$GRAF_PROM_DEPLOYMENT_NAMESPACE \
                  -o jsonpath='{.data.admin-password}' \
                     | base64 --decode | pbcopy
```

* Click `Home` and explore some of the sample dashboards e.g. `K8s/ Compute Resources/ Cluster`

![airflow-prometheus](images/airflow-prometheus.png "Airflow Prometheus")

## Notes

### Deleting pod operators

To delete kubernetes pod operators which have completed run:

```bash
NAMESPACE=default
kubectl delete pods --namespace $NAMESPACE --field-selector=status.phase=Succeeded
```

A dag to delete successfully completed pod operators is available in:

```bash
./dags/delete_successful_pod_operators.py
```

### Resetting scheduler

To reset the scheduler database run the following commands:

```bash
NAMESPACE=default
export POD_NAME=$(kubectl get pods --namespace $NAMESPACE -l "app=airflow,tier=scheduler" -o jsonpath="{.items[0].metadata.name}")
kubectl exec -it --namespace $NAMESPACE $POD_NAME -- airflow resetdb
```

Then delete the scheduler pod to restart:

```bash
kubectl delete pod --namespace $NAMESPACE $POD_NAME
```

### Scaling

The kubernetes executor requires one connection per concurrent task. The limits for CloudSQL are quite low and cannot be changed except by increasing memory. In practical terms this means that for the smallest instance you can only get 90 connections (100 connections minus 6 reserved for CloudSQL internal operations minus the webserver and scheduler). Ensure that `airflowCfg.core.dagConcurrency` is set below this limit, or else you will notice pods failing.

<https://stackoverflow.com/questions/51084907/how-to-increase-the-connection-limit-for-the-google-cloud-sql-postgres-database>

![airflow-cloudsql-connections](images/cloudsql-active-connections.png "Airflow Cloudsql Active Connections")

The default limit for pods per node is 30 when using the Azure Kubernetes Service advanced networking plugin (required for VNET for postgres). After the 10 system pods, this would limit you to 10 concurrent tasks per node (one for k8s executor, one for pod operator).

## AKS

The following script installs:

* A resource group
* A VNET for the cluster
* A three-node cluster `Standard_DS2_v2` (2 vCPU, 7GiB). Advanced networking is enabled VNET between managed postgres
* A storage account for dags and logs
* An Azure managed postgresql 10 database along with airflow username/pwd and airflow database. SSL is enforced and this connection is managed with the Balitmore root cert in the container and located at /usr/local/airflow/.postgresql/root.crt
* Enables Microsoft.SQL service endpoint on the VNET so postgres can connect
* Create a VNET rule so that postgres accepts connections from the cluster
* A kubernetes secret containing: fernet-key, sql-alchemy-conn and kubeconfig

The script takes roughly 30 minutes to complete as it waits for resources to be provisioned.

```bash
RESOURCE_GROUP=$(openssl rand -base64 10 | tr -dc 'a-z0-9-._()')
LOCATION=westeurope
STORAGE_ACCOUNT_NAME=$(openssl rand -base64 24 | tr -dc 'a-z0-9')
POSTGRES_DATABASE_INSTANCE_NAME=$(openssl rand -base64 8 | tr -dc 'a-z0-9')
NODE_VM_SIZE=Standard_DS2_v2
NODE_COUNT=3
AIRFLOW_NAMESPACE=default
./aks-sql-k8s-install.sh \
  --resource-group=$RESOURCE_GROUP \
  --location=$LOCATION \
  --storage-account-name=$STORAGE_ACCOUNT_NAME \
  --postgres-database-instance-name=$POSTGRES_DATABASE_INSTANCE_NAME \
  --node-vm-size=$NODE_VM_SIZE \
  --node-count=$NODE_COUNT \
  --airflow-namespace=$AIRFLOW_NAMESPACE
```

```bash
helm upgrade \
    --install \
    --set google.enabled=False \
    --set azure.enabled=True \
    --set azure.location=$LOCATION \
    --set azure.storageAccountName=$STORAGE_ACCOUNT_NAME \
    --set namespace=$AIRFLOW_NAMESPACE \
    airflow \
    airflow
```

## Install locally

Reset your kubernetes cluster on docker and ensure your kubeconfig is pointed to this cluster. 
The below script installs helm, a postgres helm chart and creates the necessary secrets. Then install the airflow helm chart.

```bash
./docker-sql-k8s-install.sh

DAG_FOLDER=$PWD/dags
LOG_FOLDER=/tmp/airflowLogs

helm upgrade \
    --install \
    --values airflow/local-values.yaml \
    --set local.dagFolder=$DAG_FOLDER \
    --set local.logFolder=$LOG_FOLDER \
    airflow \
    airflow
```

# To download the chart and install remotely

```bash
helm install --name airflow \
https://github.com/EamonKeane/airflow-GKE-k8sExecutor-helm/raw/master/airflow-0.1.3.tgz
```

# To fully delete a dag

```bash
DAG_FILE=airflow-log-cleanup.py
NFS_VM=airflow-vm
gcloud compute ssh $NFS_VM -- rm -f /airflow/dags/$DAG_FILE

DAG_ID=airflow-log-cleanup
NAMESPACE=airflow
export POD_NAME=$(kubectl get pods --namespace $NAMESPACE -l "app=airflow,tier=web" -o jsonpath="{.items[0].metadata.name}")
kubectl exec -it --namespace $NAMESPACE $POD_NAME -- curl -X "DELETE" http://127.0.0.1:8080/api/experimental/dags/$DAG_ID
```