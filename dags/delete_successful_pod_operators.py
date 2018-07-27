from airflow import DAG
from airflow.operators.python_operator import PythonOperator
from datetime import datetime, timedelta

default_args = {
    'owner': 'airflow',
    'depends_on_past': False,
    'start_date': datetime.utcnow(),
    'email': ['airflow@example.com'],
    'email_on_failure': False,
    'email_on_retry': False,
    'retries': 1,
    'retry_delay': timedelta(minutes=1),
}

dag = DAG(
    'delete_successful_pod_operators', default_args=default_args, schedule_interval=timedelta(minutes=5))

def cleanup_successful_pods(labels, namespace):
    """ Delete pods which have the property .status.phase=Successful with the input pod labels in the input namespace

    Args:
        labels (dict): A list of labels that match the pod's metadata.labels e.g. {'app': 'airflow-worker'}
        namespace (str): The namespace to look for successfully completed pods e.g. 'default'
    """
    from kubernetes import client, config
    from kubernetes.client.rest import ApiException
    from pprint import pprint
    config.load_incluster_config()
    v1 = client.CoreV1Api()
    print("Fetching pods from k8s API")
    ret = v1.list_namespaced_pod(namespace, watch=False)
    body = client.V1DeleteOptions()
    for i in ret.items:
        if i.metadata.labels == labels and i.status.phase == "Succeeded":
            try: 
                api_response = v1.delete_namespaced_pod(i.metadata.name, namespace, body)
                pprint(api_response)
                print("Deleting successfully completed pod %s\t%s\t%s\t%s" %
                        (i.status.pod_ip, i.metadata.namespace, i.metadata.name, i.metadata.labels))
            except ApiException as e:
                print("Exception when calling CoreV1Api->delete_namespaced_pod: %s\n" % e)
        

labels = {'app': 'airflow-worker'}
namespace = 'default'

with dag:
  delete_successful_pod_operators = PythonOperator(python_callable=cleanup_successful_pods, 
                                                    op_args=[labels, namespace], 
                                                    task_id="delete_successful_pod_operators")
  delete_successful_pod_operators
