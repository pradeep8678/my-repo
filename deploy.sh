#!/bin/bash
set -e

# -----------------------------
# Variables
# -----------------------------
PROJECT_ID="psyched-option-421700"
REGION="us-central1"
ZONE="us-central1-c"
REPO="artifact-repo"
IMAGE_NAME="simple-web-app"
COMMIT_SHA=${COMMIT_SHA:-$(git rev-parse --short HEAD)}
LIVE_MIG="my-app-blue"
IDLE_MIG="my-app-green"
LB_BACKEND="backend-service"

# -----------------------------
# Build & Push Docker Image
# -----------------------------
echo "Building Docker image..."
docker build -t asia-south1-docker.pkg.dev/$PROJECT_ID/$REPO/$IMAGE_NAME:$COMMIT_SHA .

echo "Pushing Docker image..."
docker push asia-south1-docker.pkg.dev/$PROJECT_ID/$REPO/$IMAGE_NAME:$COMMIT_SHA

# -----------------------------
# Create new Instance Template
# -----------------------------
TEMPLATE_NAME="${IMAGE_NAME}-template-$COMMIT_SHA"
echo "Creating instance template $TEMPLATE_NAME..."
gcloud compute instance-templates create $TEMPLATE_NAME \
  --machine-type=e2-small \
  --image-family=cos-stable \
  --image-project=cos-cloud \
  --boot-disk-size=20GB \
  --metadata=startup-script='#!/bin/bash
docker pull asia-south1-docker.pkg.dev/'$PROJECT_ID'/'$REPO'/'$IMAGE_NAME':'$COMMIT_SHA'
docker run -d -p 8080:8080 asia-south1-docker.pkg.dev/'$PROJECT_ID'/'$REPO'/'$IMAGE_NAME':'$COMMIT_SHA'

# -----------------------------
# Rolling update of MIG
# -----------------------------
echo "Updating MIG $IDLE_MIG with new template..."
gcloud compute instance-groups managed rolling-action replace $IDLE_MIG \
  --template=$TEMPLATE_NAME \
  --zone=$ZONE

# -----------------------------
# Swap MIGs on Load Balancer
# -----------------------------
echo "Updating LB backend..."
gcloud compute backend-services remove-backend $LB_BACKEND \
  --instance-group=$LIVE_MIG \
  --instance-group-zone=$ZONE

gcloud compute backend-services add-backend $LB_BACKEND \
  --instance-group=$IDLE_MIG \
  --instance-group-zone=$ZONE

echo "Deployment completed successfully!"
