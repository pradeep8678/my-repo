#!/bin/bash
set -e

PROJECT=$1
ZONE=$2
LIVE_MIG=$3
IDLE_MIG=$4
BACKEND=$5
COMMIT_SHA=$6

TEMPLATE_NAME="my-app-template-$COMMIT_SHA"

echo "Creating instance template $TEMPLATE_NAME..."
gcloud compute instance-templates create $TEMPLATE_NAME \
  --project=$PROJECT \
  --machine-type=e2-small \
  --image-family=cos-stable \
  --image-project=cos-cloud \
  --boot-disk-size=20GB \
  --metadata=startup-script='#!/bin/bash
docker pull asia-south1-docker.pkg.dev/'$PROJECT'/artifact-repo/simple-web-app:'$COMMIT_SHA'
docker run -d -p 8080:8080 asia-south1-docker.pkg.dev/'$PROJECT'/artifact-repo/simple-web-app:'$COMMIT_SHA

echo "Rolling update on idle MIG $IDLE_MIG..."
gcloud compute instance-groups managed rolling-action replace $IDLE_MIG \
  --template=$TEMPLATE_NAME \
  --zone=$ZONE

echo "Updating load balancer backend..."
gcloud compute backend-services remove-backend $BACKEND \
  --instance-group=$LIVE_MIG \
  --instance-group-zone=$ZONE \
  --global

gcloud compute backend-services add-backend $BACKEND \
  --instance-group=$IDLE_MIG \
  --instance-group-zone=$ZONE \
  --global

echo "Deployment complete. Switch complete!"
