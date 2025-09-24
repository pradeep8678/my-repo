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
LB_BACKEND="my-app-backend-green"
HEALTH_CHECK="my-app-hc"

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
  --size=1 \
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

# -------------------------
# Add autoscaling to new MIG
# -------------------------
echo "📈 Setting autoscaling for MIG $MIG (Target CPU 60%)"
gcloud compute instance-groups managed set-autoscaling "$MIG" \
  --max-num-replicas=5 \
  --target-cpu-utilization=0.6 \
  --zone="$ZONE" \
  --quiet

echo "⏳ Waiting for MIG $MIG to become healthy..."
gcloud compute instance-groups managed wait-until "$MIG" \
  --zone="$ZONE" \
  --stable

# -------------------------
# Detach all old MIGs including mig-green
# -------------------------
echo "🗑 Detaching old MIGs from LB backend..."
attached_migs=$(gcloud compute backend-services list-backends "$LB_BACKEND" \
  --global --format="value(group)" || true)

if [[ -n "$attached_migs" ]]; then
  for m in $attached_migs; do
    # Skip the new MIG
    if [[ "$m" == *"$MIG"* ]]; then
      continue
    fi

    echo "🛑 Detaching old MIG: $m from backend $LB_BACKEND"
    set +e
    gcloud compute backend-services remove-backend "$LB_BACKEND" \
      --instance-group="$m" \
      --instance-group-zone="$ZONE" \
      --global \
      --quiet
    set -e

    # Wait until MIG is fully detached
    echo "⏳ Waiting for $m to be detached..."
    while gcloud compute backend-services list-backends "$LB_BACKEND" \
          --global --format="value(group)" | grep -q "$m"; do
      sleep 5
    done
    echo "✅ MIG $m detached successfully."
  done
else
  echo "No old MIGs attached to backend."
fi

# -------------------------
# Delete all old MIGs including mig-green
# -------------------------
echo "🗑 Deleting old MIGs..."
old_migs=$(gcloud compute instance-groups managed list \
  --format="value(name)" \
  --filter="name~my-mig-|name:mig-green" | grep -v "$MIG" || true)

if [[ -n "$old_migs" ]]; then
  for m in $old_migs; do
    echo "🗑 Deleting old MIG: $m"
    set +e
    gcloud compute instance-groups managed delete "$m" --zone="$ZONE" --quiet
    set -e
  done
else
  echo "No old MIGs to delete."
fi

# -------------------------
# Attach new MIG to Load Balancer backend with max backend utilization
# -------------------------
echo "🔀 Attaching new MIG $MIG to backend service $LB_BACKEND"
gcloud compute backend-services add-backend "$LB_BACKEND" \
  --instance-group="$MIG" \
  --instance-group-zone="$ZONE" \
  --max-backend-utilization=0.8 \
  --global \
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
    gcloud compute instance-templates delete "$t" --quiet
    set -e
  done
else
  echo "No old templates to delete."
fi

echo "✅ Deployment completed: Blue-Green switch done!"
