#!/bin/bash
set -e

# Commit SHA from Cloud Build
COMMIT_SHA="$1"
if [[ -z "$COMMIT_SHA" ]]; then
  echo "ERROR: COMMIT_SHA not provided!"
  exit 1
fi

# Configuration
ZONE="us-central1-c"
BACKEND="my-app-lb"
MIG_BLUE="my-app-blue"
MIG_GREEN="my-app-green"

# 1. Create new instance template
TEMPLATE="my-template-$COMMIT_SHA-$(date +%s)"
echo "Creating instance template: $TEMPLATE"

gcloud compute instance-templates create "$TEMPLATE" \
  --machine-type=e2-small \
  --tags=http-server,https-server \
  --metadata=COMMIT_SHA="$COMMIT_SHA" \
  --metadata-from-file=startup-script=script.sh \
  --quiet

# 2. Determine active MIG (currently serving traffic)
ACTIVE_MIG=$(gcloud compute backend-services describe $BACKEND \
  --global \
  --format="get(backends[].group)" | grep -E "$MIG_BLUE|$MIG_GREEN" | grep -v "size=0" | awk -F'/' '{print $NF}' || true)

if [[ "$ACTIVE_MIG" == "$MIG_BLUE" ]]; then
  INACTIVE_MIG="$MIG_GREEN"
elif [[ "$ACTIVE_MIG" == "$MIG_GREEN" ]]; then
  INACTIVE_MIG="$MIG_BLUE"
else
  # First deploy, assume BLUE as initial active
  ACTIVE_MIG="$MIG_GREEN"
  INACTIVE_MIG="$MIG_BLUE"
fi

echo "Active MIG: $ACTIVE_MIG"
echo "Inactive MIG (to update): $INACTIVE_MIG"

# 3. Update inactive MIG with new template
gcloud compute instance-groups managed set-instance-template $INACTIVE_MIG \
  --template=$TEMPLATE \
  --zone=$ZONE

# 4. Scale up inactive MIG to 1 instance (or desired count)
gcloud compute instance-groups managed resize $INACTIVE_MIG --size=1 --zone=$ZONE

# 5. Wait for instances to become healthy
echo "Waiting for $INACTIVE_MIG to become healthy..."
sleep 30
gcloud compute instance-groups managed wait-until $INACTIVE_MIG --stable --zone=$ZONE

# 6. Switch backend service to new MIG
gcloud compute backend-services update $BACKEND \
  --no-enable-cdn \
  --instance-group=$INACTIVE_MIG \
  --instance-group-zone=$ZONE \
  --global

echo "Switched backend to $INACTIVE_MIG"

# 7. Scale down old MIG
gcloud compute instance-groups managed resize $ACTIVE_MIG --size=0 --zone=$ZONE
echo "Scaled down old MIG: $ACTIVE_MIG"

# 8. Cleanup old templates (keep last 3)
templates=$(gcloud compute instance-templates list \
  --filter="name~my-template-" \
  --sort-by=~creationTimestamp \
  --format="value(name)" | tail -n +4)

for t in $templates; do
  echo "Deleting old template: $t"
  gcloud compute instance-templates delete "$t" --quiet
done

echo "✅ Blue-Green Deployment complete!"
