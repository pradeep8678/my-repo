#!/bin/bash
set -e

PROJECT_ID="psyched-option-421700"
REGION="us-central1"
ZONE="us-central1-c"
REPO="artifact-repo"
IMAGE="simple-web-app"
BACKEND_SERVICE="backend-service"

# Commit SHA passed from Cloud Build substitution
COMMIT_SHA=$1
if [ -z "$COMMIT_SHA" ]; then
  echo "ERROR: Commit SHA not provided!"
  exit 1
fi

IMAGE_PATH="asia-south1-docker.pkg.dev/$PROJECT_ID/$REPO/$IMAGE:$COMMIT_SHA"

# Decide live vs idle MIGs
LIVE="my-app-blue"
IDLE="my-app-green"

if gcloud compute instance-groups managed describe $LIVE --zone $ZONE --project $PROJECT_ID >/dev/null 2>&1; then
  echo "Live MIG: $LIVE"
  echo "Idle MIG (to deploy new version): $IDLE"
else
  LIVE="my-app-green"
  IDLE="my-app-blue"
  echo "Live MIG: $LIVE"
  echo "Idle MIG (to deploy new version): $IDLE"
fi

# --- Create new instance template ---
TEMPLATE_NAME="my-app-template-$(date +%s)"

gcloud compute instance-templates create $TEMPLATE_NAME \
  --project $PROJECT_ID \
  --machine-type=e2-small \
  --image-family=debian-11 \
  --image-project=debian-cloud \
  --boot-disk-size=20GB \
  --metadata-from-file startup-script=script.sh \
  --metadata COMMIT_SHA=$COMMIT_SHA

echo "Created instance template: $TEMPLATE_NAME"

# --- Update or create the idle MIG ---
if gcloud compute instance-groups managed describe $IDLE --zone $ZONE --project $PROJECT_ID >/dev/null 2>&1; then
  echo "Updating existing MIG $IDLE"
  gcloud compute instance-groups managed rolling-action replace $IDLE \
    --zone $ZONE \
    --instance-template=$TEMPLATE_NAME \
    --max-unavailable=0 \
    --max-surge=1
else
  echo "Creating MIG: $IDLE"
  gcloud compute instance-groups managed create $IDLE \
    --zone $ZONE \
    --size 1 \
    --template $TEMPLATE_NAME
fi

# --- Wait for idle MIG to stabilize ---
echo "Waiting for MIG $IDLE to become healthy..."
gcloud compute instance-groups managed wait-until $IDLE \
  --zone $ZONE \
  --stable

# --- Switch backend service to new MIG ---
echo "Updating LB backend $BACKEND_SERVICE to point to $IDLE"
gcloud compute backend-services update-backend $BACKEND_SERVICE \
  --project $PROJECT_ID \
  --global \
  --balancing-mode UTILIZATION \
  --instance-group $IDLE \
  --instance-group-zone $ZONE \
  --capacity-scaler 1

# --- Remove old MIG from LB ---
echo "Removing old MIG $LIVE from backend $BACKEND_SERVICE"
gcloud compute backend-services remove-backend $BACKEND_SERVICE \
  --project $PROJECT_ID \
  --global \
  --instance-group $LIVE \
  --instance-group-zone $ZONE || echo "Old MIG not attached, skipping."

echo "Blue-Green Deployment completed successfully!"
