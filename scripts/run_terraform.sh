#!/bin/bash
set -e

# This script runs arbitrary terraform commands inside the CRMint CLI docker container.
# This is useful for debugging and fixing state locks (e.g. force-unlock).

# Config and defaults
CRMINT_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CRMINT_CLI_DOCKER_IMAGE=${CRMINT_CLI_DOCKER_IMAGE:-europe-docker.pkg.dev/instant-bqml-demo-environment/crmint/cli:latest}
GCLOUD_CONFIG_PATH="${CLOUDSDK_CONFIG:-$HOME/.config/gcloud}"

# Ensure .env exists
if [ ! -f "$CRMINT_HOME/cli/.env" ]; then
    echo "Error: $CRMINT_HOME/cli/.env not found."
    exit 1
fi

echo "Running terraform $@..."
docker run --rm --interactive --net=host \
  --env-file "$CRMINT_HOME/cli/.env" \
  -v "$CRMINT_HOME/cli:/app/cli" \
  -v "$CRMINT_HOME/terraform:/app/terraform" \
  -v "$GCLOUD_CONFIG_PATH:/root/.config/gcloud" \
  -w /app/terraform \
  "$CRMINT_CLI_DOCKER_IMAGE" \
  terraform "$@"
