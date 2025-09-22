#!/bin/bash
set -e

# Variables
PROJECT_ID="psyched-option-421700"
REGION="us-central1"
ZONE="us-central1-c"
REPO="asia-south1-docker.pkg.dev/$PROJECT_ID/artifact-repo/simple-web-app"
COMMIT_SHA=$1
LB_BACKEND="backend-service"   # ✅ your actual backend service

# MIG names
BLUE="my-app-blue"
GREEN="my-app-green"

# Detect which MIG is live
if gcloud compute instance-groups managed describe $BLUE --zone $ZONE --project $PROJECT_ID >/dev/null 2>&1; then
    LIVE=$BLUE
    IDLE=$GREEN
else
    LIVE=$GREEN
    IDLE=$BLUE
fi

echo "Live MIG: $LIVE"
echo "Idle MIG (to deploy new version): $IDLE"

# Create new instance template with the new image
TEMPLATE_NAME="my-app-template-$(date +%s)"
gcloud compute instance-templates create $TEMPLATE_NAME \
  --project=$PROJECT_ID \
  --machine-type=e2-small \
  --image-family=debian-11 \
  --image-project=debian-cloud \
  --boot-disk-size=10GB \
  --metadata=startup-script="#!/bin/bash
    docker-credential-gcr configure-docker
    apt-get update && apt-get install -y docker.io
    docker run -d -p 80:8080 --name simple-web-app $REPO:$COMMIT_SHA"

echo "Created instance template: $TEMPLATE_NAME"

# Create or update the idle MIG with new template
if gcloud compute instance-groups managed describe $IDLE --zone $ZONE --project $PROJECT_ID >/dev/null 2>&1; then
    echo "Updating existing MIG $IDLE"
    gcloud compute instance-groups managed rolling-action replace $IDLE \
      --zone $ZONE \
      --version template=$TEMPLATE_NAME \
      --max-unavailable=0 \
      --max-surge=1
else
    echo "Creating MIG: $IDLE"
    gcloud compute instance-groups managed create $IDLE \
      --zone $ZONE \
      --size 1 \
      --template $TEMPLATE_NAME
fi

# Wait until idle MIG is healthy
echo "Waiting for MIG $IDLE to become healthy..."
gcloud compute instance-groups managed wait-until --stable $IDLE --zone $ZONE

# Swap backend service to point to idle MIG
echo "Swapping backend service to new MIG..."
gcloud compute backend-services remove-backend $LB_BACKEND \
  --instance-group=$LIVE \
  --instance-group-zone=$ZONE \
  --global \
  --quiet || true

gcloud compute backend-services add-backend $LB_BACKEND \
  --instance-group=$IDLE \
  --instance-group-zone=$ZONE \
  --global \
  --quiet

echo "Traffic switched to $IDLE"

# Optionally delete the old MIG
echo "Deleting old MIG $LIVE..."
gcloud compute instance-groups managed delete $LIVE --zone $ZONE --quiet || true

echo "✅ Blue-Green deployment completed successfully."
