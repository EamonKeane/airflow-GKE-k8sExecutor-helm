from airflow import DAG
from datetime import datetime, timedelta
from airflow.contrib.operators.kubernetes_pod_operator import KubernetesPodOperator
from airflow.operators.dummy_operator import DummyOperator
from airflow.contrib.kubernetes.volume_mount import VolumeMount
from airflow.contrib.kubernetes.volume import Volume

default_args = {
    'owner': 'airflow',
    'depends_on_past': False,
    'start_date': datetime.utcnow(),
    'email': ['airflow@example.com'],
    'email_on_failure': False,
    'email_on_retry': False,
    'retries': 1,
    'retry_delay': timedelta(minutes=5)
}

dag = DAG(
    'kubernetes_test_podv3', default_args=default_args, schedule_interval=timedelta(minutes=10))

start = DummyOperator(task_id='run_this_first', dag=dag)

volume_mount = VolumeMount('airflow-dags',
                            mount_path='/dags',
                            sub_path='dags',
                            read_only=True)

volume_config = {
    'persistentVolumeClaim':
        {
            'claimName': 'airflow-dags'
        }
}

volume = Volume(name='airflow-dags', configs=volume_config)
file_path = "/root/kubeconfig/kubeconfig"

passing = KubernetesPodOperator(namespace='airflow',
                          image="python:3.6",
                          cmds=["python", "/dags/test-python.py"],
                          labels={"foo": "bar"},
                          name="passing-test",
                          task_id="passing-task",
                          volume_mounts=[volume_mount],
                          volumes=[volume],
                          get_logs=True,
                          in_cluster=True,
                          dag=dag
                          )

passing.set_upstream(start)