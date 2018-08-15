#!/usr/bin/env bash
# This script requires:
# azure-cli (2.0.42)
# Openssl (LibreSSL 2.2.7)
# jq-1.5

set -e

RESOURCE_GROUP=
LOCATION=
STORAGE_ACCOUNT_NAME=
POSTGRES_DATABASE_INSTANCE_NAME=
NODE_VM_SIZE=
NODE_COUNT=
AIRFLOW_NAMESPACE=
# Storage account name must be globally unique and must be between 3 and 24 characters in length and use numbers and lower-case letters only

for i in "$@"
do
case ${i} in
    -resource-group=*|--resource-group=*)
    RESOURCE_GROUP="${i#*=}"
    ;;
    -location=*|--location=*)
    LOCATION="${i#*=}"
    ;;
    -storage-account-name=*|--storage-account-name=*)
    STORAGE_ACCOUNT_NAME="${i#*=}"
    ;;
    -postgres-database-instance-name=*|--postgres-database-instance-name=*)
    POSTGRES_DATABASE_INSTANCE_NAME="${i#*=}"
    ;;
    -node-vm-size=*|--node-vm-size=*)
    NODE_VM_SIZE="${i#*=}"
    ;;
    -node-count=*|--node-count=*)
    NODE_COUNT="${i#*=}"
    ;;
    -airflow-namespace=*|--airflow-namespace=*)
    AIRFLOW_NAMESPACE="${i#*=}"
    ;;
esac
done

# Airflow Database Details
POSTGRES_AIRFLOW_DATABASE_NAME=airflow
AIRFLOW_ADMIN_NAME=airflow
POSTGRES_ADMIN_PASSWORD=$(openssl rand -base64 15)
POSTGRES_TEMPLATE_FILE_LOCATION=azure/az-airflow-postgres-resource-template.json
POSTGRES_PARAMETERS_EXAMPLE_FILE_LOCATION=azure/az-airflow-postgres-parameters.example.json
POSTGRES_PARAMETERS_NEW_FILE_LOCATION=azure/az-airflow-postgres-parameters.json

## VNET DETAILS
# https://docs.microsoft.com/en-us/cli/azure/network/vnet?view=azure-cli-latest#az-network-vnet-create
VNET_NAME=$RESOURCE_GROUP
SUBNET_NAME=$RESOURCE_GROUP
VNET_ADDRESS_PREFIXES=172.19.0.0/16
SUBNET_ADDRESS_PREFIX=172.19.0.0/16

## CLUSTER DETAILS
# https://docs.microsoft.com/en-us/cli/azure/aks?view=azure-cli-latest#az-aks-create
CLUSTER_NAME=$RESOURCE_GROUP
NODE_OSDISK_SIZE=100
KUBERNETES_VERSION=1.11.1
TAGS="client=squareroute environment=develop"
AIRFLOW_WORKER_NODE_LABEL_SELECTORS="airflow=airflow_workers pool=preemptible"
MAX_PODS=30
NETWORK_PLUGIN=azure
DOCKER_BRIDGE_ADDRESS=172.17.0.1/16
DNS_SERVICE_IP=10.2.0.10
SERVICE_CIDR=10.2.0.0/24

KUBERNETES_KUBECONFIG_SECRET=kubeconfig
TEMP_KUBECONFIG_DIR=$PWD
KUBECONFIG_FILE_OUTPUT=$TEMP_KUBECONFIG_DIR/kubeconfig

CLUSTER_RESOURCE_GROUP=MC_${RESOURCE_GROUP}_${CLUSTER_NAME}_${LOCATION}


CREATE_CLUSTER=TRUE
CREATE_STORAGE_ACCOUNT=TRUE
CREATE_VNET=TRUE
CREATE_RESOURCE_GROUP=TRUE
CREATE_DATABASE_INSTANCE=TRUE
CREATE_AIRFLOW_DATABASE=TRUE

# Create the resource group
if [ "$CREATE_RESOURCE_GROUP" = "TRUE" ]
then
az group create \
   --name $RESOURCE_GROUP \
   --location $LOCATION
fi

echo "Creating vnet for the kubernetes cluster"
# Create the vnet and subnet

if [ "$CREATE_VNET" = "TRUE" ]
then
az network vnet create \
  --name $VNET_NAME \
  --resource-group $RESOURCE_GROUP \
  --address-prefixes $VNET_ADDRESS_PREFIXES \
  --location $LOCATION \
  --subnet-name $SUBNET_NAME \
  --subnet-prefix $SUBNET_ADDRESS_PREFIX
fi

# Get the subnet ID from the produced vnet's subnet
SUBNET_ID=$(az network vnet subnet list --resource-group $RESOURCE_GROUP --vnet-name $VNET_NAME --query [].id --output tsv)
echo "Created subnet_id: ${SUBNET_ID}"

echo "Creating kubernetes cluster"
# Create the cluster
if [ "$CREATE_CLUSTER" = "TRUE" ]
then
az aks create \
    --name $CLUSTER_NAME \
    --resource-group $RESOURCE_GROUP \
    --generate-ssh-keys \
    --node-osdisk-size $NODE_OSDISK_SIZE \
    --node-vm-size $NODE_VM_SIZE \
    --node-count $NODE_COUNT \
    --network-plugin $NETWORK_PLUGIN \
    --vnet-subnet-id $SUBNET_ID \
    --kubernetes-version $KUBERNETES_VERSION \
    --max-pods $MAX_PODS \
    --location $LOCATION \
    --tags $TAGS

echo "Getting kubeconfig credentials and changing kubectl current context"
# Set the cluster as the current context in ~/.kube/config and save to a file for storing as secret in kubernetes (needed for LocalExecutor to launch pods in same cluster)
az aks get-credentials \
  --name $CLUSTER_NAME \
  --admin \
  --resource-group $RESOURCE_GROUP

az aks get-credentials \
  --name $CLUSTER_NAME \
  --admin \
  --resource-group $RESOURCE_GROUP \
  --file $KUBECONFIG_FILE_OUTPUT

echo "Initialising helm in new cluster"
# Initialise helm
kubectl --namespace kube-system create serviceaccount tiller
kubectl create clusterrolebinding tiller \
                --clusterrole cluster-admin \
                --serviceaccount=kube-system:tiller
helm init --service-account tiller
fi

if [ "$CREATE_STORAGE_ACCOUNT" = "TRUE" ]
then
echo "Creating storage account for dags and logs"
# Create a storage account for the dags and logs within the resource group
# The dynamic pvc will create volumes here based on the storage class
az storage account create \
   --resource-group $CLUSTER_RESOURCE_GROUP \
   --name $STORAGE_ACCOUNT_NAME \
   --location $LOCATION \
   --sku Standard_LRS
fi

if [ "$CREATE_DATABASE_INSTANCE" = "TRUE" ]
then
# Create the airflow database instance and airflow database within it. Uses Azure Resource Manager template in the azure directory
cp $POSTGRES_PARAMETERS_EXAMPLE_FILE_LOCATION $POSTGRES_PARAMETERS_NEW_FILE_LOCATION

jq ".parameters.serverName.value = \"$POSTGRES_DATABASE_INSTANCE_NAME\"" $POSTGRES_PARAMETERS_NEW_FILE_LOCATION > tmp.json && mv tmp.json $POSTGRES_PARAMETERS_NEW_FILE_LOCATION
jq ".parameters.location.value = \"$LOCATION\"" $POSTGRES_PARAMETERS_NEW_FILE_LOCATION > tmp.json && mv tmp.json $POSTGRES_PARAMETERS_NEW_FILE_LOCATION
jq ".parameters.administratorLogin.value = \"$AIRFLOW_ADMIN_NAME\"" $POSTGRES_PARAMETERS_NEW_FILE_LOCATION > tmp.json && mv tmp.json $POSTGRES_PARAMETERS_NEW_FILE_LOCATION

echo "Creating database instance"
az group deployment create \
  --resource-group $RESOURCE_GROUP \
  --template-file $POSTGRES_TEMPLATE_FILE_LOCATION \
  --parameters @$POSTGRES_PARAMETERS_NEW_FILE_LOCATION \
  --parameters administratorLoginPassword=$POSTGRES_ADMIN_PASSWORD
fi


if [ "$CREATE_AIRFLOW_DATABASE" = "TRUE" ]
then
echo "Creating airflow database"
az postgres db create \
  --name $POSTGRES_AIRFLOW_DATABASE_NAME \
  --resource-group $RESOURCE_GROUP \
  --server-name $POSTGRES_DATABASE_INSTANCE_NAME
fi

echo "Enabling sql service on subnet"
# Enable the sql service on the vnet
# https://docs.microsoft.com/en-us/cli/azure/network/vnet/subnet?view=azure-cli-latest#az-network-vnet-subnet-create
az network vnet subnet create \
  --resource-group $RESOURCE_GROUP \
  --name $SUBNET_NAME \
  --vnet-name $VNET_NAME \
  --address-prefix $VNET_ADDRESS_PREFIXES \
  --service-endpoints Microsoft.SQL

# This can take some time to activate, so sleep for a while.
echo "Microsoft.SQL extensions can take some time to activate, so sleep for five minutes"

secs=$((300))
while [ $secs -gt 0 ]; do
   echo -ne "$secs\033[0K\r"
   sleep 1
   : $((secs--))
done

echo "Creating vnet rule on postgres to whitelist cluster nodes"
# Create the vnet rule to allow the cluster nodes to access postgres

az postgres server vnet-rule create \
  --name $CLUSTER_NAME \
  --resource-group $RESOURCE_GROUP \
  --server-name $POSTGRES_DATABASE_INSTANCE_NAME \
  --subnet $SUBNET_ID

echo "Creating kubernetes secret for fernet key, sql_alchemy_conn and kubeconfig"
# Create the fernet key and SQL_ALCHEMY_CONN variables and store as secret in kubernetes cluster
FERNET_KEY=$(dd if=/dev/urandom bs=32 count=1 2>/dev/null | openssl base64)

POSTGRES_PORT=5432
POSTGRES_SERVICE=$(az postgres server show --name $POSTGRES_DATABASE_INSTANCE_NAME --resource-group $RESOURCE_GROUP --output json | jq .fullyQualifiedDomainName --raw-output)

SQL_ALCHEMY_CONN=postgresql+psycopg2://$AIRFLOW_ADMIN_NAME@$POSTGRES_DATABASE_INSTANCE_NAME:$POSTGRES_ADMIN_PASSWORD@$POSTGRES_SERVICE:$POSTGRES_PORT/$POSTGRES_AIRFLOW_DATABASE_NAME?sslmode=verify-full

if [ "$AIRFLOW_NAMESPACE" != "default" ]
then
kubectl create namespace $AIRFLOW_NAMESPACE
fi

kubectl create secret generic airflow \
    --namespace=$AIRFLOW_NAMESPACE \
    --from-literal=fernet-key=$FERNET_KEY \
    --from-literal=sql_alchemy_conn=$SQL_ALCHEMY_CONN \
    --from-file=kubeconfig=$KUBECONFIG_FILE_OUTPUT

echo "labelling nodes with ${AIRFLOW_WORKER_NODE_LABEL_SELECTORS} so that worker pods can be scheduled"
kubectl label nodes --overwrite --all ${AIRFLOW_WORKER_NODE_LABEL_SELECTORS}

# Remove the kubeconfig from the current directory
rm $KUBERNETES_KUBECONFIG_SECRET
