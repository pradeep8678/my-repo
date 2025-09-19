#!/bin/bash
set -e

# Variables
PROJECT_ID="psyched-option-421700"
REGION="asia-south1"
ZONE="us-central1-a"
MIG_NAME="myy-app-group"
TEMPLATE_PREFIX="simple-web-app-template"

# Generate a unique template name
TEMPLATE_NAME="${TEMPLATE_PREFIX}-$(date +%Y%m%d%H%M%S)"
echo "Creating instance template: $TEMPLATE_NAME"

# Create new instance template referencing startup.sh
gcloud compute instance-templates create "$TEMPLATE_NAME" \
  --machine-type=n1-standard-1 \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --metadata-from-file=startup-script=startup.sh

echo "Template $TEMPLATE_NAME created."

# Start rolling update on the managed instance group
gcloud compute instance-groups managed rolling-action start-update "$MIG_NAME" \
  --version template="$TEMPLATE_NAME" \
  --zone "$ZONE"

echo "Rolling update started for MIG $MIG_NAME"
