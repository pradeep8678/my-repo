#!/bin/bash
set -e

# Variables
PROJECT_ID="psyched-option-421700"
ZONE="us-central1-c"
MIG_NAME="my-app-mig"
IMAGE_NAME="asia-south1-docker.pkg.dev/${PROJECT_ID}/artifact-repo/simple-web-app"
COMMIT_SHA=${COMMIT_SHA:-$(git rev-parse --short HEAD)}
TEMPLATE_NAME="my-app-template-${COMMIT_SHA}"

echo "Deploying image with COMMIT_SHA=${COMMIT_SHA}"

# Step 1: Create instance template
gcloud compute instance-templates create "${TEMPLATE_NAME}" \
    --project="${PROJECT_ID}" \
    --machine-type=e2-small \
    --boot-disk-size=10GB \
    --boot-disk-type=pd-standard \
    --image-family=cos-stable \
    --image-project=cos-cloud \
    --metadata=startup-script="#!/bin/bash
docker-credential-gcr configure-docker
docker run -d -p 8080:8080 ${IMAGE_NAME}:${COMMIT_SHA}" \
    --tags=http-server

# Step 2: Update MIG to new template
gcloud compute instance-groups managed set-instance-template "${MIG_NAME}" \
    --zone="${ZONE}" \
    --template="${TEMPLATE_NAME}"

# Step 3: Start rolling update
gcloud compute instance-groups managed rolling-action start-update "${MIG_NAME}" \
    --zone="${ZONE}" \
    --max-surge=1 \
    --max-unavailable=0

echo "Deployment started successfully!"
