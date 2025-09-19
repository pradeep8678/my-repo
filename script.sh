#!/bin/bash
set -e

# --- Clean up any old/conflicting Docker packages ---
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
  apt-get remove -y $pkg || true
done

# --- Install prerequisites ---
apt-get update -y
apt-get install -y ca-certificates curl gnupg lsb-release

# --- Add Docker’s official GPG key ---
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

# --- Add Docker apt repo ---
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
| tee /etc/apt/sources.list.d/docker.list > /dev/null

# --- Install Docker ---
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# --- Enable & start Docker ---
systemctl enable docker
systemctl start docker

# --- Authenticate Docker with Artifact Registry ---
gcloud auth configure-docker asia-south1-docker.pkg.dev --quiet

# --- Get COMMIT_SHA from instance metadata ---
IMAGE_TAG=$(curl -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/attributes/COMMIT_SHA)

# --- Pull the Docker image ---
docker pull asia-south1-docker.pkg.dev/psyched-option-421700/artifact-repo/simple-web-app:$IMAGE_TAG

# --- Remove any existing container ---
docker rm -f simple-web-app || true

# --- Run container ---
docker run -d \
  --restart=always \
  --name simple-web-app \
  -p 80:8080 \
  asia-south1-docker.pkg.dev/psyched-option-421700/artifact-repo/simple-web-app:$IMAGE_TAG
