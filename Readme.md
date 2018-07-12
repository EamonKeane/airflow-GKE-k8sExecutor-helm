
## Cost-effect, scalable and stateless airflow

Deploy an auto-scaling, stateless airflow cluster with the kubernetes executor and CloudSQL with an SSL airflow admin page, google Oauth2 login, and an NFS server for dags in under 20 minutes. Airflow logs are stored on a google cloud bucket. The monthly cost is approximately $150 fixed, plus $0.015 per vCPU hour <https://cloud.google.com/products/calculator/#id=22a2fecd-fc97-412f-8560-1ce1f70bb44f>:

* $30/month for pre-emptible scheduler/web server node
* $70/month for 1 core CloudSQL instance
* $50/month for logs and storage

Cost per CPU Hour:

* Auto-scaling, pre-emptible `n1-highcpu-4` cost of $30/month, or $40/month assuming 75% utilisation.
* $40/(730 hours per month * 4 vCPU) = $0.015/vCPU hour

This calculation assumes you have idempotent dags, for non-idempotent dags the cost is circa $250/month + $0.05/vCPU hour. This compares with approximately $300 + $0.20/(vCPU + DB) hour with Cloud Composer <https://cloud.google.com/composer/pricing>. This tutorial installs on the free Google account ($300 over 12 months).

## Installation instructions

![airflow-gke-deployed](images/airflow-gke.png "Airflow GKE Helm")

Installation instructions:

```bash
git clone https://github.com/EamonKeane/airflow-GKE-k8sExecutor-helm.git
cd airflow-GKE-k8sExecutor-helm
```

```bash
ACCOUNT=$(gcloud config get-value core/account)
PROJECT=$(gcloud config get-value core/project)
REGION=$(gcloud config get-value compute/region)
GCE_ZONE=$(gcloud config get-value compute/zone)
DATABASE_INSTANCE_NAME=airflow
./gcloud-sql-k8s-install.sh \
    --project=$PROJECT \
    --account=$ACCOUNT \
    --gce_zone=$GCE_ZONE \
    --region=$REGION \
    --database-instance-name=$DATABASE_INSTANCE_NAME
```

## NFS Server for Dags

Please see below for the installation instructions for installing a Google Cloud [NFS Server](#NFS-Server). This is used as a temporary solution until Google Cloud Filestore comes out (circa August/September 2018) <https://cloud.google.com/filestore/>. When this comes out it will be straightforward to change a few flags in the install script to achieve a HA setup (tolerant to a full `GCE_ZONE` being wiped out). When the NFS server has been set up, run the command below to complete an installation of airflow.

```bash
helm upgrade \
    --install \
    --set google.project=$PROJECT \
    --set google.region=$REGION \
    --values my-values.yaml \
    airflow \
    airflow
```

You can change airflow/airflow.cfg and re-run the above `helm upgrade --install` command to redeploy the changes. This takes approximately 30 seconds.

Set `webScheduler.web.authenticate` to True and complete the section for SSL if you want this [SSL UI](#Exposing-oauth2-Google-ingress-with-cert-manager-and-nginx-ingress).
Alternatively to view the Dashboard UI with no authentication or SSL view:

```bash
export POD_NAME=$(kubectl get pods --namespace default -l "app=airflow,tier=web" -o jsonpath="{.items[0].metadata.name}")
echo "Visit http://127.0.0.1:8080 to use your application"
kubectl port-forward $POD_NAME 8080:8080
```

## SSL Admin UI Webpage

To expose the web server behind a https url with google oauth, please see the section for google-oauth, cert-manager and nginx-ingress install instructions [SSL UI](#Exposing-oauth2-Google-ingress-with-cert-manager-and-nginx-ingress).

## Tidying up

The easiest way to tidy-up is to delete the project and make a new one if re-deploying, however there are steps in tidying-up.sh to delete the individual resources.

## Helm chart layout

There are a few elements to the chart:

* This chart only focuses on the kubernetes executor and is tailored to run on GKE, but with some effort could be modified to run on premise or EKS/AKS.
* An NFS server is used for dags as GCE does not have a ReadWriteMany option yet (Cloud Filestore coming soon will be similar to Amazon Elastic File System and Azure File System. You need to populate this separately using e.g. Jenkins.
* Pre-install hooks add the airflow-RBAC account, dags PV, dags PVC and CloudSQL service. If the step fails at this point, you will need to remove everything before running helm again. See `tidying-up.sh` for details.
* Pre-install and pre-upgrade hook to run the alembic migrations
* Separate, templated airflow.cfg a change of which triggers a redeployment of both the web scheduler and the web server. This is due to the name of the configmap being appended with the current seconds (-{{ .Release.Time.Seconds }}) so a new configmap gets deployed each time. You may want to delete old configmaps from time to time.

## Debugging

When debugging it is useful to set the executor to LocalExecutor. This can be done by the following:

```bash
--set airflowCfg.core.executor=LocalExecutor
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
kubectl apply -f kubernetes-yaml/cluster-issuer.yaml
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

## NFS Server

```bash
NFS_DEPLOYMENT_NAME=airflow
NFS_ZONE=$GCE_ZONE
NFS_INSTANCE_NAME=myorg-airflow
STORAGE_NAME=dags
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