#!/bin/bash
set -e

ZONE="us-central1-c"
PROJECT="psyched-option-421700"
IMAGE="asia-south1-docker.pkg.dev/$PROJECT/artifact-repo/simple-web-app:$COMMIT_SHA"
LB_BACKEND="backend" # backend service of LB

# 1️⃣ Determine current live MIG (Blue or Green)
CURRENT_MIG=$(gcloud compute instance-groups managed list --filter="name~my-app-" --format="value(name)" | grep -E "blue|green" | head -1)

if [[ "$CURRENT_MIG" == *"blue"* ]]; then
  NEW_MIG="my-app-green"
else
  NEW_MIG="my-app-blue"
fi

echo "Deploying new MIG: $NEW_MIG"

# 2️⃣ Create new instance template
TEMPLATE_NAME="$NEW_MIG-template-$RANDOM"
gcloud compute instance-templates create "$TEMPLATE_NAME" \
  --machine-type=e2-small \
  --metadata=COMMIT_SHA=$COMMIT_SHA \
  --metadata-from-file=startup-script=script.sh \
  --tags=http-server,https-server \
  --quiet

# 3️⃣ Create/Update the new MIG
if gcloud compute instance-groups managed describe "$NEW_MIG" --zone $ZONE &>/dev/null; then
  echo "Updating MIG $NEW_MIG with new template"
  gcloud compute instance-groups managed rolling-action start-update "$NEW_MIG" \
    --version=template="$TEMPLATE_NAME" \
    --zone=$ZONE \
    --type=proactive \
    --max-surge=1 \
    --max-unavailable=0 \
    --quiet
else
  echo "Creating new MIG $NEW_MIG"
  gcloud compute instance-groups managed create "$NEW_MIG" \
    --base-instance-name "$NEW_MIG" \
    --size=1 \
    --template="$TEMPLATE_NAME" \
    --zone=$ZONE \
    --health-check=my-app-hc \
    --initial-delay=60 \
    --quiet
fi

# 4️⃣ Wait for new MIG instances to become healthy
echo "Waiting for new MIG $NEW_MIG to become healthy..."
sleep 60 # initial delay
gcloud compute instance-groups managed wait-until-stable "$NEW_MIG" --zone=$ZONE --quiet

# 5️⃣ Switch LB backend to new MIG
echo "Updating LB backend $LB_BACKEND to point to $NEW_MIG"
gcloud compute backend-services update "$LB_BACKEND" \
  --global \
  --instance-group="$NEW_MIG" \
  --instance-group-zone="$ZONE" \
  --quiet

# 6️⃣ Optional: delete old MIG (rollback point if needed)
OLD_MIG=$(echo "$CURRENT_MIG")
echo "Deleting old MIG $OLD_MIG"
gcloud compute instance-groups managed delete "$OLD_MIG" --zone=$ZONE --quiet

echo "Deployment completed successfully! New live MIG: $NEW_MIG"
