#!/usr/bin/env bash

if [ "$1" = "webserver" ]
then
	exec airflow webserver
fi

if [ "$1" = "scheduler" ]
then
	exec airflow scheduler
fi
if [ "$1" = "airflow initdb && alembic upgrade heads" ]
then
   cd /usr/local/lib/python3.6/site-packages/airflow/
   airflow upgradedb && alembic upgrade heads
fi