# Arc Minikube

Infrastructure setup utility for deploying GitHub Actions Runner Controller (ARC) on minikube with optional sidecar support.

## What This Does

1. Creates a minikube cluster
2. Deploys ARC (Actions Runner Controller) with GitHub App authentication
3. Optionally loads and deploys a custom sidecar container for metrics collection
4. Provides a test environment for validating sidecar-based step monitoring

## Prerequisites

- minikube
- kubectl
- helm
- docker
- A GitHub org or repo where you can register runners

## Quick Start

```bash
# 1. Set credentials (GitHub App)
# Option A: Use .env file (recommended)
cp .env.example .env
# Edit .env with your actual values

# Option B: Export environment variables
export GITHUB_CONFIG_URL=https://github.com/your-org  # or .../your-org/your-repo
export GITHUB_APP_ID=123456
export GITHUB_APP_INSTALLATION_ID=987654
export GITHUB_APP_PRIVATE_KEY_FILE=/path/to/private-key.pem

# Optional: Load a custom sidecar image
export SIDECAR_IMAGE=my-sidecar:latest

# 2. Setup everything
chmod +x setup.sh
./setup.sh setup

# 3. Copy the test workflow to your repo
cp .github/workflows/poc-test.yaml /path/to/your-repo/.github/workflows/
cd /path/to/your-repo && git add . && git commit -m "Add POC test" && git push

# 4. Trigger the workflow (GitHub UI -> Actions -> POC Test -> Run workflow)
```

## What This Enables

When used with a sidecar image, this setup provides:

- ✅ Shared `/home/runner/_work` volume for accessing action directories
- ✅ Docker socket access for monitoring container resources
- ✅ Access to `_diag/Worker_*.log` files for step timing extraction
- ✅ Isolated test environment on minikube

## Use Cases

- **Vanilla ARC Testing**: Deploy without sidecar to test basic runner functionality
- **Sidecar Development**: Load your custom sidecar image to validate metrics collection
- **CI Metrics POC**: Validate approaches for tracking action usage and resource consumption

## Cleanup

```bash
./setup.sh cleanup
```

## Files

```
.
├── setup.sh                         # Infrastructure setup script
├── .env.example                     # Template for GitHub App credentials
└── .github/workflows/poc-test.yaml  # Sample workflow for testing
```

**Note:** This repo does not contain sidecar implementation code. Build your sidecar separately and load it via the `SIDECAR_IMAGE` environment variable.
