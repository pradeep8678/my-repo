#!/bin/bash
set -e

# -------------------------
# Commit SHA from Cloud Build
# -------------------------
COMMIT_SHA="$1"
if [[ -z "$COMMIT_SHA" ]]; then
  echo "ERROR: COMMIT_SHA not provided!"
  exit 1
fi

# -------------------------
# Names & Zones
# -------------------------
TEMPLATE="my-template-$COMMIT_SHA-$(date +%s)"
ZONE="us-central1-c"
LB_BACKEND="my-app-backend-green"  # backend service name
HEALTH_CHECK="my-app-hc"           # existing health check

MIN_INSTANCES=1
MAX_INSTANCES=3
MAX_UTILIZATION=0.6  # 60%

BLUE_MIG="mig-blue"
GREEN_MIG="mig-green"

echo "🚀 Starting Blue-Green deployment with template: $TEMPLATE"

# -------------------------
# Create new instance template
# -------------------------
gcloud compute instance-templates create "$TEMPLATE" \
  --machine-type=e2-small \
  --tags=http-server,https-server \
  --metadata=COMMIT_SHA="$COMMIT_SHA" \
  --metadata-from-file=startup-script=script.sh \
  --quiet

# -------------------------
# Ensure MIGs exist (create once if missing)
# -------------------------
for MIG in "$BLUE_MIG" "$GREEN_MIG"; do
  if ! gcloud compute instance-groups managed describe "$MIG" --zone="$ZONE" >/dev/null 2>&1; then
    echo "⚙️ MIG $MIG not found. Creating..."
    gcloud compute instance-groups managed create "$MIG" \
      --base-instance-name="$MIG" \
      --size="$MIN_INSTANCES" \
      --template="$TEMPLATE" \
      --zone="$ZONE" \
      --health-check="$HEALTH_CHECK" \
      --initial-delay=30 \
      --quiet

    gcloud compute instance-groups set-named-ports "$MIG" \
      --named-ports=http:80 \
      --zone="$ZONE" \
      --quiet

    gcloud compute instance-groups managed set-autoscaling "$MIG" \
      --zone="$ZONE" \
      --min-num-replicas="$MIN_INSTANCES" \
      --max-num-replicas="$MAX_INSTANCES" \
      --target-cpu-utilization=0.6 \
      --cool-down-period=60 \
      --quiet
  else
    echo "✅ MIG $MIG already exists. Skipping creation."
  fi
done

# -------------------------
# Detect active MIG safely
# -------------------------
attached_migs=$(gcloud compute backend-services describe "$LB_BACKEND" --global --format="value(backends.group)" || true)
active_mig=""
if [[ -n "$attached_migs" ]]; then
  active_mig=$(echo "$attached_migs" | grep -E "mig-blue|mig-green" | head -n1 | xargs -r basename)
fi

if [[ "$active_mig" == "$BLUE_MIG" ]]; then
  new_mig="$GREEN_MIG"
elif [[ "$active_mig" == "$GREEN_MIG" ]]; then
  new_mig="$BLUE_MIG"
else
  echo "⚠️ No active MIG found in backend. Defaulting to $BLUE_MIG"
  new_mig="$BLUE_MIG"
fi

echo "✅ Active MIG: ${active_mig:-none}"
echo "🎯 Deploying to inactive MIG: $new_mig"

# -------------------------
# Rolling update inactive MIG
# -------------------------
echo "🔄 Updating $new_mig with template $TEMPLATE"
gcloud compute instance-groups managed rolling-action replace "$new_mig" \
  --zone="$ZONE" \
  --replacement-method=recreate \
  --max-unavailable=0 \
  --max-surge=1 \
  --quiet

echo "⏳ Waiting for $new_mig to stabilize..."
gcloud compute instance-groups managed wait-until "$new_mig" \
  --zone="$ZONE" \
  --stable

# -------------------------
# Attach new MIG to backend
# -------------------------
echo "🔀 Attaching $new_mig to backend $LB_BACKEND"
gcloud compute backend-services add-backend "$LB_BACKEND" \
  --instance-group="$new_mig" \
  --instance-group-zone="$ZONE" \
  --global \
  --quiet || true

# -------------------------
# Update backend utilization
# -------------------------
echo "🔧 Updating backend utilization for $new_mig"
gcloud compute backend-services update-backend "$LB_BACKEND" \
  --instance-group="$new_mig" \
  --instance-group-zone="$ZONE" \
  --global \
  --balancing-mode=UTILIZATION \
  --max-utilization="$MAX_UTILIZATION" \
  --quiet

# -------------------------
# Grace period before detaching old MIG
# -------------------------
echo "⏳ Waiting 30s before detaching old MIG ($active_mig)"
sleep 30

if [[ -n "$active_mig" ]]; then
  echo "🛑 Detaching old MIG: $active_mig from backend"
  gcloud compute backend-services remove-backend "$LB_BACKEND" \
    --instance-group="$active_mig" \
    --instance-group-zone="$ZONE" \
    --global \
    --quiet || true
else
  echo "No old MIG to detach."
fi

# -------------------------
# Cleanup old instance templates (keep last 3)
# -------------------------
echo "🗑 Cleaning up old templates..."
templates=$(gcloud compute instance-templates list \
  --filter="name~my-template-" \
  --sort-by=~creationTimestamp \
  --format="value(name)" | tail -n +4 || true)

if [[ -n "$templates" ]]; then
  for t in $templates; do
    echo "🗑 Deleting old template: $t"
    gcloud compute instance-templates delete "$t" --quiet || true
  done
else
  echo "No old templates to delete."
fi

echo "✅ Deployment complete! Active MIG switched to $new_mig"
