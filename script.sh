#!/bin/bash
set -e

# --- Install Docker if not present ---
if ! command -v docker >/dev/null 2>&1; then
  apt-get update -y
  apt-get install -y ca-certificates curl gnupg lsb-release
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | tee /etc/apt/sources.list.d/docker.list > /dev/null
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable docker
  systemctl start docker
fi

# --- Authenticate Docker ---
gcloud auth configure-docker asia-south1-docker.pkg.dev --quiet

# --- Get COMMIT_SHA from metadata ---
IMAGE_TAG=$(curl -sf -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/attributes/COMMIT_SHA)

# Fallback to latest if empty
if [[ -z "$IMAGE_TAG" ]]; then
  echo "WARNING: COMMIT_SHA not found, using 'latest'"
  IMAGE_TAG="latest"
fi

# --- Pull and run Docker container ---
docker pull asia-south1-docker.pkg.dev/psyched-option-421700/artifact-repo/simple-web-app:$IMAGE_TAG

docker rm -f simple-web-app || true

docker run -d \
  --restart=always \
  --name simple-web-app \
  -p 80:8080 \
  asia-south1-docker.pkg.dev/psyched-option-421700/artifact-repo/simple-web-app:$IMAGE_TAG
