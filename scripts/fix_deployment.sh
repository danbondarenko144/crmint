#!/bin/bash
set -e

# This script fixes the deployment by importing existing cloud resources into the Terraform state
# using the CRMint CLI docker image to avoid local permission/dependency issues.

# Config and defaults
CRMINT_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CRMINT_CLI_DOCKER_IMAGE=${CRMINT_CLI_DOCKER_IMAGE:-europe-docker.pkg.dev/instant-bqml-demo-environment/crmint/cli:latest}
GCLOUD_CONFIG_PATH="${CLOUDSDK_CONFIG:-$HOME/.config/gcloud}"

# Helper function to run terraform inside docker
function run_terraform {
  echo "Running terraform $1..."
  docker run --rm --interactive --net=host \
    --env-file "$CRMINT_HOME/cli/.env" \
    -v "$CRMINT_HOME/cli:/app/cli" \
    -v "$CRMINT_HOME/terraform:/app/terraform" \
    -v "$GCLOUD_CONFIG_PATH:/root/.config/gcloud" \
    -w /app/terraform \
    "$CRMINT_CLI_DOCKER_IMAGE" \
    terraform "$@"
}

# Ensure .env exists
if [ ! -f "$CRMINT_HOME/cli/.env" ]; then
    echo "Error: $CRMINT_HOME/cli/.env not found. Please run 'crmint cloud setup' at least once to generate it."
    exit 1
fi

PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
if [ -z "$PROJECT_ID" ]; then
    echo "Error: Could not determine project ID."
    exit 1
fi

echo "Fixing deployment for project: $PROJECT_ID"

# 1. Initialize
run_terraform init -upgrade

# 2. Select Workspace
echo "Selecting workspace..."
run_terraform workspace select "$PROJECT_ID" || run_terraform workspace new "$PROJECT_ID"

# 3. Import Service Accounts
echo "Importing Service Accounts..."
run_terraform import google_service_account.frontend_sa "projects/$PROJECT_ID/serviceAccounts/crmint-frontend-sa@$PROJECT_ID.iam.gserviceaccount.com" || echo "Frontend SA skipped"
run_terraform import google_service_account.jobs_sa "projects/$PROJECT_ID/serviceAccounts/crmint-jobs-sa@$PROJECT_ID.iam.gserviceaccount.com" || echo "Jobs SA skipped"
run_terraform import google_service_account.controller_sa "projects/$PROJECT_ID/serviceAccounts/crmint-controller-sa@$PROJECT_ID.iam.gserviceaccount.com" || echo "Controller SA skipped"
run_terraform import google_service_account.pubsub_sa "projects/$PROJECT_ID/serviceAccounts/crmint-pubsub-sa@$PROJECT_ID.iam.gserviceaccount.com" || echo "PubSub SA skipped"

# 4. Import Metrics and Topics
echo "Importing Resources..."
run_terraform import google_logging_metric.pipeline_status_failed "crmint/pipeline_status_failed" || echo "Metric skipped"
run_terraform import google_pubsub_topic.pipeline-finished "projects/$PROJECT_ID/topics/crmint-3-pipeline-finished" || echo "Topic skipped"

# 5. Import IAP Brand (if exists)
BRAND_NAME=$(gcloud iap oauth-brands list --format="value(name)" --limit=1 2>/dev/null)
if [ -n "$BRAND_NAME" ]; then
  echo "Found IAP Brand: $BRAND_NAME. Importing..."
  run_terraform import 'google_iap_brand.default[0]' "$BRAND_NAME" || echo "Brand skipped"
else
  echo "No existing IAP Brand found."
fi

echo "--------------------------------------------------------"
echo "Fix complete. You can now try running 'crmint cloud setup' again."
