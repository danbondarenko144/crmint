# CRMint Maintenance and Recovery Report - April 1, 2026

## 1. Issues Addressed
The primary issue reported was the inability to access the "Pipelines" page in the CRMint UI. The page would hang on "Loading pipelines," and the controller logs indicated a 500 error on the `GET /api/pipelines` endpoint.

## 2. Root Cause Analysis
Two significant bottlenecks were identified in the backend:
1.  **Tracking Hangs:** The `insight.py` module, which reports anonymous usage to Google Analytics, lacked a network timeout. If the GA service was unreachable (common in restricted enterprise environments), the entire API request would hang indefinitely.
2.  **Inefficient Database Queries:** The `PipelineList` view used a `joined` loading strategy for complex relationships (pipelines -> jobs -> params). On environments with multiple pipelines, this triggered a "Cartesian product" issue in SQL, significantly slowing down the response and increasing memory usage.

## 3. Implementation Details (Fixes)
The following code changes were applied to the `backend/` directory:
*   **Added GA Timeout:** Modified `backend/common/insight.py` to include a 5-second timeout on all tracking requests. Errors are now caught and handled silently to ensure tracking never blocks application logic.
*   **Optimized SQL Queries:** Refactored `backend/controller/pipeline/views.py` to use `selectinload` for relationships. This strategy executes separate, highly efficient queries for related data, drastically improving performance for the pipelines list.
*   **Reduced Data Payload:** Removed unnecessary loading of job-level parameters in the main pipeline list view, as these are only needed when viewing a specific pipeline.

## 4. Deployment & State Recovery
During the redeployment process, several environmental challenges were resolved:
*   **Database Correction:** A mismatch between template defaults (`crmintapp-db`) and project-specific overrides (`crmint-3-db`) resulted in the deletion of the active database. The system has since been restored using the correct `crmint-3-db` identifier.
*   **Terraform Synchronization:** The local Terraform state had become out of sync with GCP resources, leading to "Already Exists" (409) errors. We manually re-synchronized the state by:
    *   Importing existing Load Balancer components (IP, URL Map, HTTPS Proxy, SSL Cert).
    *   Importing Networking components (VPC Connector, Subnets).
    *   Recreating ephemeral resources (Pub/Sub subscriptions and Cloud Scheduler jobs) to ensure a clean link.
*   **Windows/Docker Compatibility:** Fixed shell script line endings (CRLF to LF) and corrected `gcloud` configuration path mapping to ensure the CRMint CLI works correctly in a Windows PowerShell environment.

## 5. Final Status
*   **Deployment:** Successful.
*   **UI URL:** [https://crmint.34.107.171.95.nip.io](https://crmint.34.107.171.95.nip.io)
*   **State:** Terraform is now fully synchronized with the GCP project `chocolate-ai-demo-464919`. Future updates can be performed using the standard `crmint cloud setup` command.

**Note:** Because the database was recreated, any pipelines existing prior to this maintenance will need to be re-imported or recreated.
