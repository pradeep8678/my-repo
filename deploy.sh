#!/bin/bash
set -e

if [ -z "$COMMIT_SHA" ]; then
  echo "ERROR: Commit SHA not provided!"
  exit 1
fi

echo "Deploying version with commit SHA: $COMMIT_SHA"

# Create new instance template
gcloud compute instance-templates create my-app-template-$COMMIT_SHA \
  --machine-type=e2-small \
  --image-family=debian-11 \
  --image-project=debian-cloud \
  --boot-disk-size=10GB \
  --metadata-from-file startup-script=script.sh \
  --tags=http-server

# Update GREEN MIG (idle group)
gcloud compute instance-groups managed rolling-action replace my-app-green \
  --template=my-app-template-$COMMIT_SHA \
  --zone=us-central1-c

# Switch traffic from BLUE to GREEN
gcloud compute backend-services set-backend backend-service \
  --global \
  --instance-group=my-app-green \
  --instance-group-zone=us-central1-c

echo "✅ Deployment complete. Traffic switched to GREEN (commit $COMMIT_SHA)."
