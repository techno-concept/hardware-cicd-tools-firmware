#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="ghcr.io/techno-concept/firmware-builder:latest"

DOCKER_DIR="${SCRIPT_DIR}/actions/github/firmware/build-docker"

if [ ! -d "$DOCKER_DIR" ]; then
    echo "❌ Error: Directory $DOCKER_DIR not found."
    exit 1
fi

cd "$DOCKER_DIR"
echo "🛠️  Building Docker image: ${IMAGE_NAME}..."
docker build -t "${IMAGE_NAME}" .
echo "✅ Docker image built successfully!"
