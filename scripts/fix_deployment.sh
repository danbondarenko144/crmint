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

  
  # Default variables needed for validation during import
  USER_EMAIL=$(gcloud config get-value account 2>/dev/null)
  PROJECT_ID_VAR=$(gcloud config get-value project 2>/dev/null)
  
  docker run --rm --interactive --net=host \
    --env-file "$CRMINT_HOME/cli/.env" \
    -e TF_VAR_project_id="$PROJECT_ID_VAR" \
    -e TF_VAR_app_title="CRMint" \
    -e TF_VAR_iap_support_email="$USER_EMAIL" \
    -e TF_VAR_notification_sender_email="$USER_EMAIL" \
    -e TF_VAR_iap_allowed_users="[\"user:$USER_EMAIL\"]" \
    -e TF_VAR_report_usage_id="false" \
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
 
# Nav to terraform dir to clean locks
cd "$CRMINT_HOME/terraform"
if ls .terraform.tfstate.lock.info 1> /dev/null 2>&1; then
    echo "Removing stale lock file .terraform.tfstate.lock.info..."
    sudo rm .terraform.tfstate.lock.info
fi
find . -name "*.lock.info" -exec echo "Removing stale lock: {}" \; -exec sudo rm {} \;
cd - > /dev/null

# 1. Initialize
run_terraform init -upgrade

# 2. Select Workspace
echo "Selecting workspace..."
run_terraform workspace select "$PROJECT_ID" || run_terraform workspace new "$PROJECT_ID"

# Temporarily allow failures for import commands since resources might already be managed
set +e

# 3. Import Service Accounts
echo "Importing Service Accounts..."
run_terraform import google_service_account.frontend_sa "projects/$PROJECT_ID/serviceAccounts/crmint-frontend-sa@$PROJECT_ID.iam.gserviceaccount.com" || echo "Frontend SA skipped (already managed?)"
run_terraform import google_service_account.jobs_sa "projects/$PROJECT_ID/serviceAccounts/crmint-jobs-sa@$PROJECT_ID.iam.gserviceaccount.com" || echo "Jobs SA skipped (already managed?)"
run_terraform import google_service_account.controller_sa "projects/$PROJECT_ID/serviceAccounts/crmint-controller-sa@$PROJECT_ID.iam.gserviceaccount.com" || echo "Controller SA skipped (already managed?)"
run_terraform import google_service_account.pubsub_sa "projects/$PROJECT_ID/serviceAccounts/crmint-pubsub-sa@$PROJECT_ID.iam.gserviceaccount.com" || echo "PubSub SA skipped (already managed?)"

# 4. Import Metrics and Topics
echo "Importing Resources..."
run_terraform import google_logging_metric.pipeline_status_failed "crmint/pipeline_status_failed" || echo "Metric skipped (already managed?)"
run_terraform import google_pubsub_topic.pipeline-finished "projects/$PROJECT_ID/topics/crmint-3-pipeline-finished" || echo "Topic skipped (already managed?)"

# 5. Import IAP Brand (if exists)
BRAND_NAME=$(gcloud iap oauth-brands list --format="value(name)" --limit=1 2>/dev/null)
if [ -n "$BRAND_NAME" ]; then
  echo "Found IAP Brand: $BRAND_NAME. Importing..."
  run_terraform import 'google_iap_brand.default[0]' "$BRAND_NAME" || echo "Brand skipped (already managed?)"
else
  echo "No existing IAP Brand found."
fi

# 6. Import Global Address (IP)
echo "Checking for Global Address 'crmint-ip'..."
IP_EXISTS=$(gcloud compute addresses list --filter="name=crmint-ip" --format="value(name)" --global 2>/dev/null)
if [ -n "$IP_EXISTS" ]; then
  echo "Found Global Address: $IP_EXISTS. Importing..."
  run_terraform import google_compute_global_address.default "projects/$PROJECT_ID/global/addresses/crmint-ip" || echo "Global Address skipped (already managed?)"
else
  echo "No existing Global Address found."
fi

set -e

echo "--------------------------------------------------------"
echo "Fix complete. You can now try running 'crmint cloud setup' again."
