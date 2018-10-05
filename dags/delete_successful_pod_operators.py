from airflow import DAG
from airflow.operators.python_operator import PythonOperator
from datetime import datetime, timedelta
import logging

default_args = {
    'owner': 'airflow',
    'depends_on_past': False,
    'start_date': datetime(2018, 7, 27, 13),
    'email': ['alerts@logistio.ie'],
    'email_on_failure': False,
    'email_on_retry': False,
    'retries': 1,
    'retry_delay': timedelta(minutes=1),
}

dag = DAG(
    'delete_successful_pod_operators', 
    default_args=default_args, 
    schedule_interval=timedelta(minutes=5),
    catchup=False)

def cleanup_successful_pods(labels, namespace, **kwargs):
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
    logging.info('Fetching pods from k8s API')
    ret = v1.list_namespaced_pod(namespace, watch=False)
    body = client.V1DeleteOptions()
    prev_execution_date = kwargs['prev_execution_date']
    for i in ret.items:
        logging.info(i.metadata.name)
        logging.info(i.status.container_statuses[0].state)
        terminated = i.status.container_statuses[0].state.terminated
        if terminated is not None:
            # Delete pods that are more than five minutes old with a finish status of 
            # completed on the first container (pod operators only contain one container)
            # Previously there was a race condition where pods would be deleted before 
            # the airflow-worker could read their exit status
            if terminated.finished_at <= prev_execution_date:
                if i.metadata.labels == labels and i.status.phase == "Succeeded":
                    try: 
                        api_response = v1.delete_namespaced_pod(i.metadata.name, namespace, body)
                        pprint(api_response)
                        logging.info("Deleting successfully completed pod %s\t%s\t%s\t%s" %
                                (i.status.pod_ip, i.metadata.namespace, i.metadata.name, i.metadata.labels))
                    except ApiException as e:
                        logging.info("Exception when calling CoreV1Api->delete_namespaced_pod: %s\n" % e)
        
with dag:
  labels = {'foo': 'bar'}
  namespace = 'default'

  delete_successful_python_pod_operators = PythonOperator(python_callable=cleanup_successful_pods, 
                                                    op_args=[labels, namespace], 
                                                    provide_context=True,
                                                    task_id="delete_successful_python_pod_operators")
  delete_successful_python_pod_operators

  labels = {'airflow-worker'}
  namespace = 'airflow'

  delete_successful_k8s_executor_workers = PythonOperator(python_callable=cleanup_successful_pods, 
                                                          op_args=[labels, namespace], 
                                                          provide_context=True,
                                                          task_id="delete_successful_k8s_executor_workers")

  delete_successful_k8s_executor_workers