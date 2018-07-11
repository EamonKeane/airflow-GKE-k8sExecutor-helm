AIRFLOW_NFS_VM_NAME=icabbi-airflow-vm
PROJECT=icabbi-202810
ZONE=europe-west2-c

EXTERNAL_IP=35.189.81.147
INTERNAL_IP=10.154.0.7

gcloud compute instances \
   describe $AIRFLOW_NFS_VM_NAME \
   --zone=$ZONE \
   --format='value(networkInterfaces[0].networkIP)'

#    gcloud compute --project "icabbi-202810" ssh --zone "europe-west2-c" "icabbi-airflow-vm"