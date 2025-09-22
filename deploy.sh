#!/bin/bash
set -e

# Commit SHA passed from Cloud Build
COMMIT_SHA=$1

# Make a safe template name (start with letter, use only letters, numbers, hyphens)
SAFE_SHA=$(echo $COMMIT_SHA | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g')
TEMPLATE_NAME="my-app-template-${SAFE_SHA}"

# Variables
MIG_NAME=${_MIG_NAME}
ZONE=${_ZONE}
IMAGE="asia-south1-docker.pkg.dev/psyched-option-421700/artifact-repo/simple-web-app:${COMMIT_SHA}"

echo "Deploying version with commit SHA: $COMMIT_SHA"
echo "Using instance template: $TEMPLATE_NAME"

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
