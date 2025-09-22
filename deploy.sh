#!/bin/bash
set -e

# Variables
PROJECT_ID="psyched-option-421700"
REGION="asia-south1"
ZONE="asia-south1-a"
MIG_NAME="my-app-mig"
IMAGE_NAME="asia-south1-docker.pkg.dev/${PROJECT_ID}/artifact-repo/simple-web-app"
COMMIT_SHA=${COMMIT_SHA:-$(git rev-parse --short HEAD)}
TEMPLATE_NAME="my-app-template-${COMMIT_SHA}"

echo "Deploying image with COMMIT_SHA=${COMMIT_SHA}"

# Step 1: Create a new instance template
echo "Creating instance template: ${TEMPLATE_NAME}"
gcloud compute instance-templates create "${TEMPLATE_NAME}" \
    --project="${PROJECT_ID}" \
    --machine-type=e2-small \
    --region="${REGION}" \
    --network=default \
    --maintenance-policy=MIGRATE \
    --image-family=cos-stable \
    --image-project=cos-cloud \
    --boot-disk-size=10GB \
    --boot-disk-type=pd-standard \
    --metadata=startup-script="#!/bin/bash
docker-credential-gcr configure-docker
docker run -d -p 8080:8080 ${IMAGE_NAME}:${COMMIT_SHA}" \
    --tags=http-server

# Step 2: Update the Managed Instance Group
echo "Updating Managed Instance Group: ${MIG_NAME}"
gcloud compute instance-groups managed rolling-action replace "${MIG_NAME}" \
    --region="${REGION}" \
    --template="${TEMPLATE_NAME}"

echo "Deployment started successfully!"
