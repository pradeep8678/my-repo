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
MIG="my-mig-$COMMIT_SHA-$(date +%s)"
ZONE="us-central1-c"
LB_BACKEND="my-app-backend-green"  # existing backend service
HEALTH_CHECK="my-app-hc"           # existing health check

MIN_INSTANCES=1
MAX_INSTANCES=3
MAX_UTILIZATION=0.6  # 60% for LB backend

echo "✅ Creating instance template: $TEMPLATE"

# -------------------------
# Create new instance template
# -------------------------
gcloud compute instance-templates create "$TEMPLATE" \
  --machine-type=e2-small \
  --tags=http-server,https-server \
  --metadata=COMMIT_SHA="$COMMIT_SHA" \
  --metadata-from-file=startup-script=script.sh \
  --quiet

echo "✅ Creating new Managed Instance Group: $MIG"

# -------------------------
# Create new MIG with health check
# -------------------------
gcloud compute instance-groups managed create "$MIG" \
  --base-instance-name="$MIG" \
  --size="$MIN_INSTANCES" \
  --template="$TEMPLATE" \
  --zone="$ZONE" \
  --health-check="$HEALTH_CHECK" \
  --initial-delay=30 \
  --quiet

# -------------------------
# Add named port mapping (http → 80)
# -------------------------
echo "🔧 Setting named port 'http:80' for MIG $MIG"
gcloud compute instance-groups set-named-ports "$MIG" \
  --named-ports=http:80 \
  --zone="$ZONE" \
  --quiet

echo "⏳ Waiting for MIG $MIG to become healthy..."
gcloud compute instance-groups managed wait-until "$MIG" \
  --zone="$ZONE" \
  --stable

# -------------------------
# Enable autoscaling for the new MIG
# -------------------------
echo "⚙️ Setting autoscaling for MIG $MIG (min: $MIN_INSTANCES, max: $MAX_INSTANCES)"
gcloud compute instance-groups managed set-autoscaling "$MIG" \
  --zone="$ZONE" \
  --min-num-replicas="$MIN_INSTANCES" \
  --max-num-replicas="$MAX_INSTANCES" \
  --target-cpu-utilization=0.6 \
  --cool-down-period=60 \
  --quiet

# -------------------------
# Detach all old MIGs from backend safely
# -------------------------
echo "🗑 Detaching old MIGs from LB backend..."
attached_migs=$(gcloud compute backend-services describe "$LB_BACKEND" --global --format="value(backends.group)" || true)

if [[ -n "$attached_migs" ]]; then
  IFS=";" read -ra MIG_ARRAY <<< "$attached_migs"
  for m in "${MIG_ARRAY[@]}"; do
    MIG_NAME=$(basename "$m")

    # Skip the new MIG
    if [[ "$MIG_NAME" == "$MIG" ]]; then
      continue
    fi

    echo "🛑 Detaching old MIG: $MIG_NAME from backend $LB_BACKEND"
    set +e
    gcloud compute backend-services remove-backend "$LB_BACKEND" \
      --instance-group="$MIG_NAME" \
      --instance-group-zone="$ZONE" \
      --global \
      --quiet || true
    set -e

    # Wait until MIG is fully detached
    echo "⏳ Waiting for $MIG_NAME to be detached..."
    while gcloud compute backend-services describe "$LB_BACKEND" --global --format="value(backends.group)" | grep -q "$MIG_NAME"; do
      sleep 5
    done
    echo "✅ MIG $MIG_NAME detached successfully."
  done
else
  echo "No old MIGs attached to backend."
fi

# -------------------------
# Delete all old MIGs
# -------------------------
echo "🗑 Deleting old MIGs..."
old_migs=$(gcloud compute instance-groups managed list \
  --format="value(name)" \
  --filter="name~my-mig-" | grep -v "$MIG" || true)

if [[ -n "$old_migs" ]]; then
  for m in $old_migs; do
    echo "🗑 Deleting old MIG: $m"
    set +e
    # Delete autoscaler first if exists
    gcloud compute autoscalers delete "$m" --zone="$ZONE" --quiet || true
    # Then delete MIG
    gcloud compute instance-groups managed delete "$m" --zone="$ZONE" --quiet || true
    set -e
  done
else
  echo "No old MIGs to delete."
fi

# -------------------------
# Attach new MIG to Load Balancer backend
# -------------------------
echo "🔀 Attaching new MIG $MIG to backend service $LB_BACKEND"
gcloud compute backend-services add-backend "$LB_BACKEND" \
  --instance-group="$MIG" \
  --instance-group-zone="$ZONE" \
  --global \
  --quiet

# -------------------------
# Update backend max utilization (60%)
# -------------------------
echo "🔧 Setting max backend utilization ($MAX_UTILIZATION) for LB backend $LB_BACKEND"
gcloud compute backend-services update "$LB_BACKEND" \
  --global \
  --balancing-mode=UTILIZATION \
  --max-utilization="$MAX_UTILIZATION" \
  --quiet

# -------------------------
# Cleanup old instance templates (keep last 3)
# -------------------------
echo "🗑 Deleting old instance templates..."
templates=$(gcloud compute instance-templates list \
  --filter="name~my-template-" \
  --sort-by=~creationTimestamp \
  --format="value(name)" | tail -n +4 || true)

if [[ -n "$templates" ]]; then
  for t in $templates; do
    echo "🗑 Deleting old template: $t"
    set +e
    gcloud compute instance-templates delete "$t" --quiet || true
    set -e
  done
else
  echo "No old templates to delete."
fi

echo "✅ Deployment completed: Blue-Green switch with autoscaling and 60% backend utilization done!"
