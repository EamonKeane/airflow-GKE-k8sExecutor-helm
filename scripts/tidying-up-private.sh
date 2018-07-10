#!/usr/bin/env bash

ACCOUNT=eamon@logistio.ie
PROJECT="icabbi-202810"
REGION="europe-west2"
GCE_ZONE="europe-west2-c"
DATABASE_INSTANCE_NAME=icabbiairflow4

./tidying-up.sh --project=$PROJECT -gce_zone=$GCE_ZONE --region=$REGION --database_instance_name=$DATABASE_INSTANCE_NAME


