
# Cost-effective, scalable and stateless airflow

Deploy a highly-available, auto-scaling, stateless airflow cluster with the kubernetes executor and CloudSQL. This also includes an SSL airflow admin page, google Oauth2 login, and Cloud Filestore for storing dags and logs and can be completed in under 20 minutes. The monthly fixed cost is approximately $180 at the cheapest to $500/month for a HA version (default installation shown here, $240/month Cloud Filestore minimum), plus $0.015 per vCPU hour <https://cloud.google.com/products/calculator/#id=22a2fecd-fc97-412f-8560-1ce1f70bb44f>:

  Cheapest:

* $30/month for pre-emptible scheduler/web server node
* $30/month for single node NFS
* $70/month for 1 core CloudSQL instance
* $50/month for logs and storage

  Cost per CPU Hour:

* Auto-scaling, pre-emptible `n1-highcpu-4` cost of $30/month, or $40/month assuming 75% utilisation.
* $40/(730 hours per month * 4 vCPU) = $0.015/vCPU hour

This calculation assumes you have idempotent dags, for non-idempotent dags the cost is circa $0.05/vCPU hour. This compares with approximately $300 + $0.20/(vCPU + DB)hour with Cloud Composer <https://cloud.google.com/composer/pricing>. This tutorial installs on the free Google account ($300 over 12 months).

## Installation instructions

![airflow-gke-deployed](images/airflow-gke.png "Airflow GKE Helm")

Pre-requisites:

* Ensure you have helm (v2.9.1), kubectl (v1.11.0), openssl, gcloud SDK (v208.0.1)
* Ensure the Cloud SQL Admin API has been enabled on your project (<https://cloud.google.com/sql/docs/mysql/admin-api/>)

Installation instructions:

```bash
git clone https://github.com/EamonKeane/airflow-GKE-k8sExecutor-helm.git
cd airflow-GKE-k8sExecutor-helm
```

The following script by default installs:

* A HA postgres CloudSql instance along with cloudsql service account, airflow database and password
* A 3-zone regional kubernetes cluster
* An auto-scaling worker pool for dag tasks (starts at zero, take 2 minutes to spin up when first dag is triggered)
* A kubernetes secret containing the sql_alchemy_conn, fernet key, gcs-log-folder name, cloudsql service account and the cluster's kubeconfig (for the Kube Pod Operator with local executor)
* A Cloud Filestore instance

```bash
# NOTE cloud filestore is only available in the following areas, so choose another region as necessary if your currently configured region is not listed
# asia-eas1, europe-west1, europe-west3, europe-west4, us-central1
# us-east1, us-west1, us-west2
ACCOUNT=$(gcloud config get-value core/account)
PROJECT=$(gcloud config get-value core/project)
REGION=$(gcloud config get-value compute/region)
GCE_ZONE=$(gcloud config get-value compute/zone)
DATABASE_INSTANCE_NAME=airflow
CLOUD_FILESTORE_ZONE=$(gcloud config get-value compute/region)
HIGHLY_AVAILABLE=TRUE
./gcloud-sql-k8s-install.sh \
    --project=$PROJECT \
    --account=$ACCOUNT \
    --gce-zone=$GCE_ZONE \
    --region=$REGION \
    --database-instance-name=$DATABASE_INSTANCE_NAME \
    --cloud-filestore-zone=$CLOUD_FILESTORE_ZONE \
    --highly-available=$HIGHLY_AVAILABLE
```

```bash
CLOUD_FILESTORE_IP=$(gcloud beta filestore instances describe airflow \
                                      --project=$PROJECT \
                                      --location=$CLOUD_FILESTORE_ZONE \
                                      --format json | jq .networks[0].ipAddresses[0] --raw-output)
```

For airflow to be able to write to Cloud Filestore, you need to change the permissions on the NFS(<https://cloud.google.com/filestore/docs/quickstart-console>).
Follow the instructions below [Cloud Filestore Permissions](#Setting-file-permissions-on-Cloud-Filestore):

If not using Cloud Filestore, see below for the installation instructions for installing a Google Cloud [NFS Server](#NFS-Server).

# Setting file permissions on Cloud Filestore

Create a VM to mount the file share and make the required changes.

```bash
VM_NAME=change-permissions
gcloud compute --project=$PROJECT instances create $VM_NAME --zone=$GCE_ZONE
```

SSH into the machine

```bash
gcloud compute ssh $VM_NAME --zone=$GCE_ZONE --project=$PROJECT
```

Copy and paste the following into the terminal:

```bash
sudo apt-get -y update
sudo apt-get -y install nfs-common
```

Then copy and paste the following (substituting your `$CLOUD_FILESTORE_IP` for the ip address):

```bash
CLOUD_FILESTORE_IP=
sudo mkdir /mnt/test
sudo mount $CLOUD_FILESTORE_IP:/airflow /mnt/test
sudo mkdir /mnt/test/dags
sudo mkdir /mnt/test/logs
sudo chmod go+rw /mnt/test/dags
sudo chmod go+rw /mnt/test/logs
```

Then delete the VM:

```bash
gcloud compute instances delete $VM_NAME --zone=$GCE_ZONE --project=$PROJECT
```

## Install the helm chart

```bash
helm upgrade \
    --install \
    --set google.project=$PROJECT \
    --set google.region=$REGION \
    --set dagVolume.nfsServer=$CLOUD_FILESTORE_IP \
    --set logVolume.nfsServer=$CLOUD_FILESTORE_IP \
    airflow \
    airflow
```

You can change `airflow/airflow.cfg` and re-run the above `helm upgrade --install` command to redeploy the changes. This takes approximately 30 seconds.

Quickly copy the example dags folder here to the NFS by using `kubectl cp`:

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

Set  if you want an [SSL UI].

To expose the web server behind a https url with google oauth, set `webScheduler.web.authenticate` to `True` and see the section for google-oauth, cert-manager and nginx-ingress install instructions [SSL UI](#Exposing-oauth2-Google-ingress-with-cert-manager-and-nginx-ingress).

## Tidying up

The easiest way to tidy-up is to delete the project and make a new one if re-deploying, however there are steps in `tidying-up.sh` to delete the individual resources.

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
