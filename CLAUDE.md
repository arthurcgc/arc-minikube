# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an infrastructure setup utility for deploying GitHub Actions Runner Controller (ARC) on minikube with optional sidecar support. The repo provides a streamlined way to test and develop sidecar-based metrics collection for GitHub Actions runners.

## Prerequisites

- minikube
- kubectl
- helm
- docker
- A GitHub org or repo where you can register runners

## Architecture

The project consists of a single main component:

**Infrastructure Setup** ([setup.sh](setup.sh)): Bash script that orchestrates the test environment - creates a minikube cluster, optionally loads a sidecar Docker image, and deploys ARC (Actions Runner Controller) with or without the sidecar container.

**Key Points:**

- This repo does NOT contain sidecar implementation code
- Sidecar images are built externally and loaded via `SIDECAR_IMAGE` env var
- Can deploy vanilla ARC (no sidecar) or ARC with custom sidecar
- When sidecar is deployed, it gets access to `/home/runner/_work` volume and Docker socket

## Common Commands

```bash
# Setup ARC without sidecar (vanilla deployment)
./setup.sh setup

# Setup ARC with custom sidecar
export SIDECAR_IMAGE=my-sidecar:latest
./setup.sh setup

# Watch sidecar logs from runner pods (if sidecar is deployed)
kubectl logs -f -n arc-runners -l "actions.github.com/scale-set-name=arc-runner-set" -c step-exporter

# Cleanup minikube cluster
./setup.sh cleanup
```

## Kubernetes Commands

```bash
# Check runner pods
kubectl get pods -n arc-runners -l "actions.github.com/scale-set-name=arc-runner-set"

# View sidecar logs directly
kubectl logs <pod-name> -n arc-runners -c step-exporter

# View runner logs
kubectl logs <pod-name> -n arc-runners -c runner

# Check what images are loaded in minikube
minikube -p gha-poc image ls
```

## Key Implementation Details

### Authentication

- Uses GitHub App authentication instead of PAT
- Requires: App ID, Installation ID, and private key PEM file
- The app needs Actions (read/write) and Administration (read/write) permissions
- Credentials via `.env` file (recommended) or environment variables
- `.env` is automatically loaded by `setup.sh` and gitignored

### Sidecar Deployment (when SIDECAR_IMAGE is set)

- Image is loaded into minikube with `minikube image load`
- Sidecar runs with `imagePullPolicy: Never` (uses pre-loaded image)
- Gets read-only access to `/home/runner/_work` mounted at `/work`
- Gets read-only access to Docker socket at `/var/run/docker.sock`
- Resource limits: 200m CPU, 128Mi memory
- Runs in same pod as runner, shares emptyDir volume

### Volume Mounts

The runner and sidecar share access to:

- `/home/runner/_work` - Contains action directories, `_actions` subdirectory with `.completed` files, and `_diag` logs
- `/var/run/docker.sock` - Docker daemon socket for monitoring DinD containers

### Useful Implementation Patterns (for sidecar developers)

- Action completion timestamps: `/work/_actions/{owner}/{action}/v{version}.completed` files
- Step timing logs: `/work/_diag/Worker_*.log` files with StepsRunner events
- Step start regex: `[.*?INFO\s+StepsRunner\]\s+Starting:\s+(.+)$`
- Step finish regex: `[.*?INFO\s+StepsRunner\]\s+Finishing:\s+(.+?)\s+\((\w+)\)$`
- Docker API via `/var/run/docker.sock` for container metrics (CPU, memory, image names)

## Testing Workflow

To test with a sidecar:

1. Build your sidecar image separately (in another repo)
2. Load it: `export SIDECAR_IMAGE=my-sidecar:latest`
3. Run: `./setup.sh setup`
4. Copy [.github/workflows/poc-test.yaml](.github/workflows/poc-test.yaml) to your target repository
5. Trigger the workflow (must use `runs-on: arc-runner-set`)
6. Watch output: `kubectl logs -f -n arc-runners -l "actions.github.com/scale-set-name=arc-runner-set" -c step-exporter`

The test workflow includes steps with varying durations (2s, 5s, 10 minutes) to validate metrics collection.
