#!/bin/bash
set -e

# Generate random template name
TEMPLATE="my-template-$RANDOM"
echo "Creating instance template: $TEMPLATE"

gcloud compute instance-templates create "$TEMPLATE" \
  --machine-type=e2-small \
  --tags=http-server,https-server \
  --metadata-from-file=startup-script=script.sh \
  --quiet

echo "Rolling update MIG my-app to template: $TEMPLATE"
gcloud compute instance-groups managed rolling-action start-update my-app \
  --version=template="$TEMPLATE" \
  --zone=us-central1-c \
  --type=proactive \
  --max-surge=1 \
  --max-unavailable=0 \
  --quiet

# Optional cleanup: keep last 3 templates
templates=$(gcloud compute instance-templates list \
  --filter="name~my-template-" \
  --sort-by=~creationTimestamp \
  --format="value(name)" | tail -n +4)
for t in $templates; do
  echo "Deleting old template: $t"
  gcloud compute instance-templates delete "$t" --quiet
done
