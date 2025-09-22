#!/bin/bash
set -e

# Ensure COMMIT_SHA is provided
if [ -z "$COMMIT_SHA" ]; then
  echo "Error: COMMIT_SHA is not set!"
  exit 1
fi

IMAGE="asia-south1-docker.pkg.dev/${_PROJECT_ID}/artifact-repo/simple-web-app:${COMMIT_SHA}"
TEMPLATE_NAME="my-app-template-${COMMIT_SHA}"

echo "Creating instance template: $TEMPLATE_NAME with image: $IMAGE"

# Create a new instance template with the latest Docker image
gcloud compute instance-templates create "$TEMPLATE_NAME" \
    --machine-type=e2-small \
    --image-family=cos-stable \
    --image-project=cos-cloud \
    --boot-disk-size=20GB \
    --metadata=startup-script='#!/bin/bash
      docker-credential-gcr configure-docker
      docker pull '"$IMAGE"'
      docker run -d -p 8080:8080 '"$IMAGE"'' \
    --region=${_ZONE%-*} # extract region from zone

echo "Updating Managed Instance Group: $_MIG_NAME"

# Perform rolling update
gcloud compute instance-groups managed rolling-action replace $_MIG_NAME \
    --region=${_ZONE%-*} \
    --max-surge=1 \
    --max-unavailable=1 \
    --template="$TEMPLATE_NAME"

echo "Deployment complete!"
