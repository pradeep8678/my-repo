#!/bin/bash
set -e

# Variables
PROJECT_ID="${_PROJECT_ID}"
ZONE="${_ZONE}"
MIG_NAME="${_MIG_NAME}"
IMAGE="asia-south1-docker.pkg.dev/${PROJECT_ID}/artifact-repo/simple-web-app:${COMMIT_SHA}"
TEMPLATE_NAME="my-app-template-${COMMIT_SHA}"

if [ -z "$COMMIT_SHA" ]; then
  echo "Error: COMMIT_SHA is not set!"
  exit 1
fi

echo "Creating instance template: $TEMPLATE_NAME"

gcloud compute instance-templates create "$TEMPLATE_NAME" \
    --project="$PROJECT_ID" \
    --machine-type=e2-small \
    --network=default \
    --metadata=startup-script="#!/bin/bash
        apt-get update && apt-get install -y docker.io
        docker pull $IMAGE
        docker run -d -p 8080:8080 $IMAGE" \
    --tags=http-server

echo "Updating managed instance group: $MIG_NAME"
gcloud compute instance-groups managed rolling-action replace "$MIG_NAME" \
    --zone="$ZONE" \
    --version=template="$TEMPLATE_NAME"

echo "Deployment complete!"
