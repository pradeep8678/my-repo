#!/bin/bash
set -e

# Commit SHA from Cloud Build
COMMIT_SHA="$1"
if [[ -z "$COMMIT_SHA" ]]; then
  echo "ERROR: COMMIT_SHA not provided!"
  exit 1
fi

# Generate unique names
TEMPLATE="my-template-$COMMIT_SHA-$(date +%s)"
MIG="my-mig-$COMMIT_SHA-$(date +%s)"
REGION="us-central1"
ZONE="us-central1-c"
LB_BACKEND="mig-green"

echo "Creating instance template: $TEMPLATE"

# Create new instance template
gcloud compute instance-templates create "$TEMPLATE" \
  --machine-type=e2-small \
  --tags=http-server,https-server \
  --metadata=COMMIT_SHA="$COMMIT_SHA" \
  --metadata-from-file=startup-script=script.sh \
  --quiet

echo "Creating new MIG: $MIG"
gcloud compute instance-groups managed create "$MIG" \
  --base-instance-name="$MIG" \
  --size=1 \
  --template="$TEMPLATE" \
  --zone="$ZONE" \
  --quiet

echo "Waiting for MIG $MIG to become healthy..."
gcloud compute instance-groups managed wait-until "$MIG" \
  --zone="$ZONE" \
  --stable

echo "Updating Load Balancer backend to new MIG..."
gcloud compute backend-services add-backend "$LB_BACKEND" \
  --instance-group="$MIG" \
  --instance-group-zone="$ZONE" \
  --global \
  --quiet

# Optional: remove old MIGs (keep latest 1)
old_migs=$(gcloud compute instance-groups managed list \
  --format="value(name)" \
  --filter="name~my-mig-" | grep -v "$MIG")

for m in $old_migs; do
  echo "Deleting old MIG: $m"
  gcloud compute instance-groups managed delete "$m" --zone="$ZONE" --quiet
done

# Optional: cleanup old templates (keep last 3)
templates=$(gcloud compute instance-templates list \
  --filter="name~my-template-" \
  --sort-by=~creationTimestamp \
  --format="value(name)" | tail -n +4)
for t in $templates; do
  echo "Deleting old template: $t"
  gcloud compute instance-templates delete "$t" --quiet
done
