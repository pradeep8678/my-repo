#!/bin/bash
set -e

# Get the current Git commit SHA for tagging
COMMIT_SHA=$(git rev-parse --short HEAD)
echo "Deploying commit: $COMMIT_SHA"

# Docker image name
IMAGE="asia-south1-docker.pkg.dev/psyched-option-421700/artifact-repo/simple-web-app:$COMMIT_SHA"

echo "Building Docker image..."
docker build -t $IMAGE .

echo "Pushing Docker image to Artifact Registry..."
docker push $IMAGE

echo "Creating new instance template..."
gcloud compute instance-templates create my-app-template-$COMMIT_SHA \
  --machine-type=e2-small \
  --boot-disk-size=20GB \
  --image-project=cos-cloud \
  --image-family=cos-stable \
  --metadata=startup-script='#!/bin/bash
    docker-credential-gcr configure-docker
    docker pull '"$IMAGE"'
    docker run -d -p 8080:80 '"$IMAGE"''

echo "Starting rolling update on MIG..."
gcloud compute instance-groups managed rolling-action start-update my-app \
  --version=template=my-app-template-$COMMIT_SHA \
  --zone=us-central1-c \
  --max-surge=1 \
  --max-unavailable=0

echo "Deployment triggered successfully!"
