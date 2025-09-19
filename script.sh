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

# --- Install Docker Engine + CLI + containerd + Buildx + Compose ---
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# --- Enable & start Docker ---
systemctl enable docker
systemctl start docker

# --- Authenticate Docker with Artifact Registry ---
gcloud auth configure-docker asia-south1-docker.pkg.dev --quiet

# --- Pull latest image ---
docker pull asia-south1-docker.pkg.dev/psyched-option-421700/artifact-repo/simple-web-app:latest

# --- Remove any existing container (safe cleanup) ---
docker rm -f simple-web-app || true

# --- Run container: host port 80 → container port 8080, auto-restart on reboot ---
docker run -d \
  --restart=always \
  --name simple-web-app \
  -p 80:8080 \
  asia-south1-docker.pkg.dev/psyched-option-421700/artifact-repo/simple-web-app:latest
