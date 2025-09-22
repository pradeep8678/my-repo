#!/bin/bash
set -e

# Variables
PROJECT_ID="psyched-option-421700"
REGION="us-central1"
ZONE="us-central1-c"
REPO_NAME="artifact-repo"
IMAGE_NAME="simple-web-app"
LB_BACKEND="backend-service"
LIVE_MIG="my-app-blue"
IDLE_MIG="my-app-green"

# Get commit SHA
COMMIT_SHA=$(git rev-parse HEAD)
echo "Deploying version with commit SHA: $COMMIT_SHA"

# Build Docker image
docker build -t asia-south1-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/$IMAGE_NAME:$COMMIT_SHA .

# Push Docker image
docker push asia-south1-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/$IMAGE_NAME:$COMMIT_SHA

# Create new instance template
gcloud compute instance-templates create my-app-template-$COMMIT_SHA \
  --project=$PROJECT_ID \
  --machine-type=e2-small \
  --image-family=cos-stable \
  --image-project=cos-cloud \
  --boot-disk-size=20GB \
  --metadata=startup-script='#!/bin/bash
docker pull asia-south1-docker.pkg.dev/'$PROJECT_ID'/'$REPO_NAME'/'$IMAGE_NAME':'$COMMIT_SHA'
docker run -d -p 8080:8080 asia-south1-docker.pkg.dev/'$PROJECT_ID'/'$REPO_NAME'/'$IMAGE_NAME':'$COMMIT_SHA''

# Update idle MIG with new template
gcloud compute instance-groups managed rolling-action replace $IDLE_MIG \
  my-app-template-$COMMIT_SHA \
  --zone=$ZONE

# Wait until idle MIG is stable
echo "Waiting for $IDLE_MIG to become healthy..."
gcloud compute instance-groups managed wait-until-stable $IDLE_MIG --zone=$ZONE

# Swap MIGs in backend service
echo "Swapping backend from $LIVE_MIG to $IDLE_MIG"
gcloud compute backend-services remove-backend $LB_BACKEND \
  --instance-group=$LIVE_MIG --instance-group-zone=$ZONE

gcloud compute backend-services add-backend $LB_BACKEND \
  --instance-group=$IDLE_MIG --instance-group-zone=$ZONE

# Optionally, rename MIGs for next deploy
TEMP=$LIVE_MIG
LIVE_MIG=$IDLE_MIG
IDLE_MIG=$TEMP

echo "Deployment complete!"
