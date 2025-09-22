#!/bin/bash
set -e

# Validate required variables
if [ -z "$COMMIT_SHA" ]; then
  echo "Error: COMMIT_SHA is not set!"
  exit 1
fi
if [ -z "$MIG_NAME" ]; then
  echo "Error: MIG_NAME is not set!"
  exit 1
fi
if [ -z "$ZONE" ]; then
  echo "Error: ZONE is not set!"
  exit 1
fi
if [ -z "$PROJECT_ID" ]; then
  echo "Error: PROJECT_ID is not set!"
  exit 1
fi

IMAGE="asia-south1-docker.pkg.dev/${PROJECT_ID}/artifact-repo/simple-web-app:${COMMIT_SHA}"
TEMPLATE_NAME="my-app-template-${COMMIT_SHA}"
REGION="${ZONE%-*}"

echo "Creating instance template: $TEMPLATE_NAME with image: $IMAGE"

gcloud compute instance-templates create "$TEMPLATE_NAME" \
    --machine-type=e2-small \
    --image-family=cos-stable \
    --image-project=cos-cloud \
    --boot-disk-size=20GB \
    --metadata=startup-script='#!/bin/bash
      docker-credential-gcr configure-docker
      docker pull '"$IMAGE"'
      docker run -d -p 8080:8080 '"$IMAGE"'' \
    --project="$PROJECT_ID"

echo "Updating Managed Instance Group: $MIG_NAME"

# Correct way to update MIG to new template
gcloud compute instance-groups managed update "$MIG_NAME" \
    --region="$REGION" \
    --template="$TEMPLATE_NAME" \
    --max-surge=1 \
    --max-unavailable=1 \
    --project="$PROJECT_ID"

echo "Deployment complete!"
