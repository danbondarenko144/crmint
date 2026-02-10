#!/bin/bash
set -e

# This script attempts to fix the Terraform state by importing existing resources
# that were created in a previous failed run but not recorded in the state file.

PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
if [ -z "$PROJECT_ID" ]; then
    echo "Error: Could not determine project ID. Please run 'gcloud config set project YOUR_PROJECT_ID' first."
    exit 1
fi

echo "Fixing deployment for project: $PROJECT_ID"

# Navigate to terraform directory
cd "$(dirname "$0")/../terraform"

echo "Initializing Terraform..."
terraform init -upgrade

# Select or create workspace matching the project ID
echo "Selecting workspace..."
terraform workspace select $PROJECT_ID || terraform workspace new $PROJECT_ID

echo "Importing Service Accounts..."
# Frontend SA
terraform import google_service_account.frontend_sa "projects/$PROJECT_ID/serviceAccounts/crmint-frontend-sa@$PROJECT_ID.iam.gserviceaccount.com" || echo "Frontend SA skipped/already imported"
# Jobs SA
terraform import google_service_account.jobs_sa "projects/$PROJECT_ID/serviceAccounts/crmint-jobs-sa@$PROJECT_ID.iam.gserviceaccount.com" || echo "Jobs SA skipped/already imported"
# Controller SA
terraform import google_service_account.controller_sa "projects/$PROJECT_ID/serviceAccounts/crmint-controller-sa@$PROJECT_ID.iam.gserviceaccount.com" || echo "Controller SA skipped/already imported"
# PubSub SA
terraform import google_service_account.pubsub_sa "projects/$PROJECT_ID/serviceAccounts/crmint-pubsub-sa@$PROJECT_ID.iam.gserviceaccount.com" || echo "PubSub SA skipped/already imported"

echo "Importing Logging Metrics..."
terraform import google_logging_metric.pipeline_status_failed "crmint/pipeline_status_failed" || echo "Metric skipped/already imported"

echo "Importing PubSub Topic..."
terraform import google_pubsub_topic.pipeline-finished "projects/$PROJECT_ID/topics/crmint-3-pipeline-finished" || echo "Topic skipped/already imported"

echo "Checking for IAP Brand..."
# IAP Brand can be tricky as the ID is not the project ID. We need to query it.
BRAND_NAME=$(gcloud iap oauth-brands list --format="value(name)" --limit=1 2>/dev/null)

if [ -n "$BRAND_NAME" ]; then
  echo "Found IAP Brand: $BRAND_NAME. Importing..."
  terraform import 'google_iap_brand.default[0]' "$BRAND_NAME" || echo "Brand skipped/already imported"
else
  echo "No existing IAP Brand found. Terraform will create one."
fi

echo "--------------------------------------------------------"
echo "Fix complete. You can now try running 'crmint cloud setup' again."
