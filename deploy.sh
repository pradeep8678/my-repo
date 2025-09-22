#!/bin/bash
set -e

# Variables
PROJECT_ID="psyched-option-421700"
ZONE="asia-south1-a"
MIG_NAME="my-app-mig"
IMAGE="asia-south1-docker.pkg.dev/$PROJECT_ID/artifact-repo/simple-web-app:$COMMIT_SHA"
TEMPLATE_NAME="my-app-template-$COMMIT_SHA"

# 1. Create new instance template
echo "Creating instance template: $TEMPLATE_NAME"
gcloud compute instance-templates create $TEMPLATE_NAME \
    --project=$PROJECT_ID \
    --machine-type=e2-small \
    --network=default \
    --metadata=startup-script="#!/bin/bash
        docker-credential-gcr configure-docker
        docker pull $IMAGE
        docker run -d -p 8080:8080 $IMAGE" \
    --tags=http-server \
    --zone=$ZONE

# 2. Update MIG to use new template
echo "Updating MIG: $MIG_NAME to use template $TEMPLATE_NAME"
gcloud compute instance-groups managed rolling-action replace $MIG_NAME \
    --zone=$ZONE \
    --version=template=$TEMPLATE_NAME

echo "Deployment complete!"
