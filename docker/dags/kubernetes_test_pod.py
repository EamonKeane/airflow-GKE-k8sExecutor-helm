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
    'kubernetes_test_pod', default_args=default_args, schedule_interval=timedelta(minutes=10))

start = DummyOperator(task_id='run_this_first', dag=dag)

volume_mount = VolumeMount('airflow-dags',
                            mount_path='/dags',
                            sub_path=None,
                            read_only=True)

volume_config = {
    'persistentVolumeClaim':
        {
            'claimName': 'airflow-dags'
        }
}

volume = Volume(name='airflow-dags', configs=volume_config)

passing = KubernetesPodOperator(namespace='default',
                          image="python:3.6",
                          cmds=["python", "dags/test_python.py"],
                          labels={"foo": "bar"},
                          name="passing-test",
                          task_id="passing-task",
                          volumes=[volume],
                          get_logs=True,
                          in_cluster=True,
                          dag=dag
                          )

passing.set_upstream(start)