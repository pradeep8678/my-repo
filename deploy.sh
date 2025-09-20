#!/bin/bash
set -e

# Unique template name using commit + timestamp
TEMPLATE="my-template-${COMMIT_SHA:0:7}-$(date +%s)"

echo ">>> Creating instance template: $TEMPLATE"

gcloud compute instance-templates create "$TEMPLATE" \
  --machine-type=e2-small \
  --metadata=COMMIT_SHA=$COMMIT_SHA \
  --metadata-from-file=startup-script=script.sh \
  --tags=http-server,https-server \
  --quiet

echo ">>> Rolling update MIG my-app to template: $TEMPLATE"

gcloud compute instance-groups managed rolling-action start-update my-app \
  --version=template="$TEMPLATE" \
  --zone=us-central1-c \
  --type=proactive \
  --max-surge=1 \
  --max-unavailable=0 \
  --quiet

echo ">>> Cleanup: keeping only last 3 templates"
templates=$(gcloud compute instance-templates list \
  --filter="name~my-template-" \
  --sort-by=~creationTimestamp \
  --format="value(name)" | tail -n +4)

for t in $templates; do
  echo "Deleting old template: $t"
  gcloud compute instance-templates delete "$t" --quiet
done
