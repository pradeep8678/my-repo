#!/bin/bash
set -e

# Commit SHA passed from Cloud Build
COMMIT_SHA=$1

# Variables
MIG_NAME=${_MIG_NAME}
TEMPLATE_NAME="${_TEMPLATE_NAME_PREFIX}-${COMMIT_SHA}"
ZONE=${_ZONE}
IMAGE="asia-south1-docker.pkg.dev/psyched-option-421700/artifact-repo/simple-web-app:${COMMIT_SHA}"

echo "Deploying version with commit SHA: $COMMIT_SHA"

# 1. Create a new instance template with the new Docker image
gcloud compute instance-templates create $TEMPLATE_NAME \
    --machine-type=e2-small \
    --image-family=cos-stable \
    --image-project=cos-cloud \
    --boot-disk-size=20GB \
    --metadata=startup-script="#!/bin/bash
docker-credential-gcr configure-docker
docker pull ${IMAGE}
docker run -d -p 8080:8080 ${IMAGE}"

# 2. Update the MIG to use the new template
gcloud compute instance-groups managed rolling-action replace $MIG_NAME \
    --template=$TEMPLATE_NAME \
    --zone=$ZONE

echo "Deployment triggered successfully."
