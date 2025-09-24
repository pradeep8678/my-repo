#!/bin/bash
set -e

# Commit SHA from Cloud Build
COMMIT_SHA="$1"
if [[ -z "$COMMIT_SHA" ]]; then
  echo "ERROR: COMMIT_SHA not provided!"
  exit 1
fi

# Generate unique instance template name
TEMPLATE="my-template-$COMMIT_SHA-$(date +%s)"
echo "Creating instance template: $TEMPLATE"

# Create instance template with startup script & COMMIT_SHA metadata
gcloud compute instance-templates create "$TEMPLATE" \
  --machine-type=e2-small \
  --tags=http-server,https-server \
  --metadata=COMMIT_SHA="$COMMIT_SHA" \
  --metadata-from-file=startup-script=script.sh \
  --quiet

echo "Forcing MIG replacement with template: $TEMPLATE"
gcloud compute instance-groups managed rolling-action replace my-app \
  --version=template="$TEMPLATE" \
  --zone=us-central1-c \
  --max-unavailable=100% \
  --max-surge=0 \
  --quiet


# Optional: cleanup old templates (keep last 3)
templates=$(gcloud compute instance-templates list \
  --filter="name~my-template-" \
  --sort-by=~creationTimestamp \
  --format="value(name)" | tail -n +4)
for t in $templates; do
  echo "Deleting old template: $t"
  gcloud compute instance-templates delete "$t" --quiet
done
