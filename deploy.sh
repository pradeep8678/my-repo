#!/bin/bash
set -e

# Configs
LB_BACKEND="backend"          # Your LB backend service name
ZONE="us-central1-c"          # MIG zone
MACHINE_TYPE="e2-small"       # VM type
TEMPLATE_PREFIX="my-app"      # Prefix for instance templates and MIGs
MIG_PREFIX="my-app"           # Prefix for MIG names
DESIRED_SIZE=1                # Desired number of VMs per MIG

# Determine current live MIG
BLUE_MIG="${MIG_PREFIX}-blue"
GREEN_MIG="${MIG_PREFIX}-green"

LIVE_MIG=""
IDLE_MIG=""

if gcloud compute instance-groups managed describe "$BLUE_MIG" --zone="$ZONE" &>/dev/null; then
    LIVE_MIG="$BLUE_MIG"
    IDLE_MIG="$GREEN_MIG"
elif gcloud compute instance-groups managed describe "$GREEN_MIG" --zone="$ZONE" &>/dev/null; then
    LIVE_MIG="$GREEN_MIG"
    IDLE_MIG="$BLUE_MIG"
else
    # No MIG exists yet; first deployment
    LIVE_MIG=""
    IDLE_MIG="$BLUE_MIG"
fi

echo "Live MIG: $LIVE_MIG"
echo "Idle MIG (to deploy new version): $IDLE_MIG"

# Create new instance template for idle MIG
TEMPLATE_NAME="${TEMPLATE_PREFIX}-template-$(date +%s)"
echo "Creating instance template: $TEMPLATE_NAME"

gcloud compute instance-templates create "$TEMPLATE_NAME" \
    --machine-type="$MACHINE_TYPE" \
    --metadata-from-file=startup-script=script.sh \
    --tags=http-server,https-server \
    --quiet

# Create new MIG or resize if exists
if gcloud compute instance-groups managed describe "$IDLE_MIG" --zone="$ZONE" &>/dev/null; then
    echo "MIG $IDLE_MIG exists, updating template"
    gcloud compute instance-groups managed set-instance-template "$IDLE_MIG" \
        --template="$TEMPLATE_NAME" \
        --zone="$ZONE" \
        --quiet
    gcloud compute instance-groups managed resize "$IDLE_MIG" \
        --size="$DESIRED_SIZE" \
        --zone="$ZONE" \
        --quiet
else
    echo "Creating MIG: $IDLE_MIG"
    gcloud compute instance-groups managed create "$IDLE_MIG" \
        --base-instance-name="$IDLE_MIG" \
        --template="$TEMPLATE_NAME" \
        --size="$DESIRED_SIZE" \
        --zone="$ZONE" \
        --quiet
fi

# Wait for MIG to become healthy
echo "Waiting for MIG $IDLE_MIG to become healthy..."
gcloud compute instance-groups managed wait-until --stable "$IDLE_MIG" --zone="$ZONE"

# Switch LB backend to point to new MIG
if [ -n "$LIVE_MIG" ]; then
    echo "Removing old MIG $LIVE_MIG from LB backend $LB_BACKEND"
    gcloud compute backend-services remove-backend "$LB_BACKEND" \
        --instance-group="$LIVE_MIG" \
        --instance-group-zone="$ZONE" \
        --global
fi

echo "Adding new MIG $IDLE_MIG to LB backend $LB_BACKEND"
gcloud compute backend-services add-backend "$LB_BACKEND" \
    --instance-group="$IDLE_MIG" \
    --instance-group-zone="$ZONE" \
    --global

# Optional: delete old MIG
if [ -n "$LIVE_MIG" ]; then
    echo "Deleting old MIG $LIVE_MIG"
    gcloud compute instance-groups managed delete "$LIVE_MIG" --zone="$ZONE" --quiet
fi

echo "Blue-Green deployment completed successfully!"
