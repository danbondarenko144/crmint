# Guide: Switching from Remote to Local Images

This guide documents the process of switching CRMint from using pre-built remote images (which may become unreachable due to project suspensions) to building and hosting images within your own Google Cloud Project.

## 1. Building the CRMint CLI Locally
If the default `crmint` CLI image is unreachable, you must build it from the source code in the `cli/` directory.

### Build Command
Run this from the root of the project:
```powershell
docker build -t crmint-cli:latest -f cli/Dockerfile .
```

### PowerShell Integration
To make the local CLI easy to use, define this function in your PowerShell session (or add it to your `$PROFILE`):
```powershell
function crmint {
    # Path to your local gcloud config
    $GCLOUD_CONFIG = "C:/Users/dan.bondarenko/AppData/Roaming/gcloud"
    
    docker run --rm -it --net=host `
        -v "${PWD}/cli:/app/cli" `
        -v "${PWD}/terraform:/app/terraform" `
        -v "${GCLOUD_CONFIG}:/root/.config/gcloud" `
        -e "GOOGLE_CLOUD_SDK=/google-cloud-sdk" `
        crmint-cli:latest crmint $args
}
```

## 2. Setting up your Artifact Registry
You must host the application images in your own project.

### Create Repository
```powershell
gcloud artifacts repositories create crmint `
    --repository-format=docker `
    --location=europe `
    --description="CRMint Docker repository"
```

### Configure Docker Auth
```powershell
gcloud auth configure-docker europe-docker.pkg.dev
```

## 3. Building and Pushing Application Images
Package your local code changes (e.g., the SQL optimizations and GA timeout fixes) into new images.

```powershell
$PROJECT_ID = "chocolate-ai-demo-464919"

# Controller
docker build -t "europe-docker.pkg.dev/$PROJECT_ID/crmint/controller:dev" -f ./backend/controller.Dockerfile ./backend
docker push "europe-docker.pkg.dev/$PROJECT_ID/crmint/controller:dev"

# Jobs
docker build -t "europe-docker.pkg.dev/$PROJECT_ID/crmint/jobs:dev" -f ./backend/jobs.Dockerfile ./backend
docker push "europe-docker.pkg.dev/$PROJECT_ID/crmint/jobs:dev"

# Frontend
docker build -t "europe-docker.pkg.dev/$PROJECT_ID/crmint/frontend:dev" -f ./frontend/Dockerfile ./frontend
docker push "europe-docker.pkg.dev/$PROJECT_ID/crmint/frontend:dev"
```

## 4. Updating the Deployment Configuration
The "stage" file (`.tfvars.json`) must be updated to point to these new locations.

1.  Locate your stage file in `cli/stages/<PROJECT_ID>.tfvars.json`.
2.  Update the image paths to match your project and the `:dev` tag:
    ```json
    {
      "frontend_image": "europe-docker.pkg.dev/chocolate-ai-demo-464919/crmint/frontend:dev",
      "controller_image": "europe-docker.pkg.dev/chocolate-ai-demo-464919/crmint/controller:dev",
      "jobs_image": "europe-docker.pkg.dev/chocolate-ai-demo-464919/crmint/jobs:dev"
    }
    ```

## 5. Deployment
Once the images are pushed and the stage file is updated, deploy using the local CLI:
```powershell
crmint cloud setup
```

## 6. Synchronizing State (Terraform Import)
If you encounter "Already Exists" (409) errors during deployment, it means your local Terraform state is missing resources that are already present in GCP. You can "link" them using the `import` command.

### Example Command
```powershell
docker run --rm -it -v "${PWD}/terraform:/app/terraform" -v "${PWD}/cli:/app/cli" -v "C:/Users/dan.bondarenko/AppData/Roaming/gcloud:/root/.config/gcloud" crmint-cli:latest terraform -chdir=terraform import -var-file=/app/cli/stages/chocolate-ai-demo-464919.tfvars.json google_compute_global_address.default chocolate-ai-demo-464919/global-crmint-default
```

### Command Breakdown
*   `docker run`: Starts a new container session.
*   `--rm`: Automatically removes the container after the command finishes to save disk space.
*   `-it`: Runs in interactive mode (allowing you to answer any Terraform prompts).
*   `-v "${PWD}/terraform:/app/terraform"`: Mounts your local Terraform code into the container.
*   `-v "${PWD}/cli:/app/cli"`: Mounts your local CLI/Stages folder into the container.
*   `-v "C:/.../gcloud:/root/.config/gcloud"`: **Critical:** Links your local Google Cloud credentials so the container is authenticated as you.
*   `crmint-cli:latest`: Uses the CLI image you built locally.
*   `terraform`: The tool to execute inside the container.
*   `-chdir=terraform`: Tells Terraform to look for `.tf` files in the `/app/terraform` folder.
*   `import`: The command to add existing resources to the state.
*   `-var-file=...`: Loads your project-specific variables (like Project ID and Region) so Terraform knows how to connect.
*   `google_compute_global_address.default`: The name of the resource in your Terraform code.
*   `chocolate-ai-demo-464919/global-crmint-default`: The actual ID of the resource as it appears in Google Cloud.

## Summary of Benefits
*   **Independence:** You are no longer dependent on the `instant-bqml-demo-environment` project.
*   **Customization:** You can apply and deploy your own code fixes immediately.
*   **Reliability:** The environment is fully contained within your own GCP project and local machine.
