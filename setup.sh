#!/bin/bash
set -euo pipefail

# Load .env if it exists
if [[ -f .env ]]; then
    export $(grep -v '^#' .env | xargs)
fi

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
die()  { echo -e "${RED}[x]${NC} $*"; exit 1; }

PROFILE="arc-minikube"
RUNNER_NS="arc-runners"
CONTROLLER_NS="arc-systems"

usage() {
    cat <<EOF
Usage: $0 <command>

Commands:
  setup       Create minikube cluster + deploy ARC with sidecar
  watch       Tail sidecar logs from runner pods
  cleanup     Delete minikube cluster

Required env vars for setup:
  GITHUB_CONFIG_URL              - Org or repo URL (https://github.com/your-org)
  GITHUB_APP_ID                  - GitHub App ID
  GITHUB_APP_INSTALLATION_ID     - GitHub App Installation ID
  GITHUB_APP_PRIVATE_KEY_FILE    - Path to GitHub App private key PEM file

Optional env vars:
  SIDECAR_IMAGE                  - Custom sidecar image to load (e.g., my-sidecar:latest)

Example:
  export GITHUB_CONFIG_URL=https://github.com/myorg
  export GITHUB_APP_ID=123456
  export GITHUB_APP_INSTALLATION_ID=987654
  export GITHUB_APP_PRIVATE_KEY_FILE=/path/to/key.pem
  export SIDECAR_IMAGE=my-sidecar:latest  # optional
  ./setup.sh setup
  # Trigger workflow with 'runs-on: arc-runner-set'
EOF
}

check_deps() {
    for cmd in minikube kubectl helm docker; do
        command -v "$cmd" &>/dev/null || die "Missing: $cmd"
    done
}

create_cluster() {
    if minikube status -p "$PROFILE" &>/dev/null; then
        log "Minikube cluster '$PROFILE' already exists"
    else
        log "Creating minikube cluster..."
        minikube start --profile="$PROFILE" --cpus=2 --memory=4096 --driver=docker
    fi
    minikube profile "$PROFILE"
}

load_sidecar_image() {
    if [[ -n "${SIDECAR_IMAGE:-}" ]]; then
        log "Loading sidecar image: $SIDECAR_IMAGE"
        minikube -p "$PROFILE" image load "$SIDECAR_IMAGE"
    else
        log "No SIDECAR_IMAGE provided, skipping sidecar"
    fi
}

deploy_arc() {
    [[ -z "${GITHUB_CONFIG_URL:-}" ]] && die "Set GITHUB_CONFIG_URL"
    [[ -z "${GITHUB_APP_ID:-}" ]] && die "Set GITHUB_APP_ID"
    [[ -z "${GITHUB_APP_INSTALLATION_ID:-}" ]] && die "Set GITHUB_APP_INSTALLATION_ID"
    [[ -z "${GITHUB_APP_PRIVATE_KEY_FILE:-}" ]] && die "Set GITHUB_APP_PRIVATE_KEY_FILE"
    [[ ! -f "${GITHUB_APP_PRIVATE_KEY_FILE}" ]] && die "Private key file not found: $GITHUB_APP_PRIVATE_KEY_FILE"

    log "Installing ARC controller..."
    helm upgrade --install arc \
        oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller \
        --namespace "$CONTROLLER_NS" \
        --create-namespace \
        --wait

    log "Creating runner namespace and secret..."
    kubectl create namespace "$RUNNER_NS" 2>/dev/null || true
    kubectl delete secret github-app-secret -n "$RUNNER_NS" 2>/dev/null || true
    kubectl create secret generic github-app-secret \
        --namespace="$RUNNER_NS" \
        --from-literal=github_app_id="$GITHUB_APP_ID" \
        --from-literal=github_app_installation_id="$GITHUB_APP_INSTALLATION_ID" \
        --from-file=github_app_private_key="$GITHUB_APP_PRIVATE_KEY_FILE"

    if [[ -n "${SIDECAR_IMAGE:-}" ]]; then
        log "Deploying runner scale set with sidecar..."
        helm upgrade --install arc-runner-set \
            oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set \
            --namespace "$RUNNER_NS" \
            --set githubConfigUrl="$GITHUB_CONFIG_URL" \
            --set githubConfigSecret.github_app_id="$GITHUB_APP_ID" \
            --set githubConfigSecret.github_app_installation_id="$GITHUB_APP_INSTALLATION_ID" \
            --set githubConfigSecret.github_app_private_key="$(cat $GITHUB_APP_PRIVATE_KEY_FILE)" \
            --set minRunners=0 \
            --set maxRunners=2 \
            --values - \
            --wait <<YAML
template:
  spec:
    containers:
      - name: runner
        image: ghcr.io/actions/actions-runner:latest
        command: ["/home/runner/run.sh"]
        volumeMounts:
          - name: work
            mountPath: /home/runner/_work
          - name: docker-sock
            mountPath: /var/run/docker.sock
      - name: step-exporter
        image: ${SIDECAR_IMAGE}
        imagePullPolicy: Never
        volumeMounts:
          - name: work
            mountPath: /work
            readOnly: true
          - name: docker-sock
            mountPath: /var/run/docker.sock
            readOnly: true
        resources:
          limits:
            cpu: 200m
            memory: 128Mi
    volumes:
      - name: work
        emptyDir: {}
      - name: docker-sock
        hostPath:
          path: /var/run/docker.sock
          type: Socket
YAML
    else
        log "Deploying runner scale set without sidecar..."
        helm upgrade --install arc-runner-set \
            oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set \
            --namespace "$RUNNER_NS" \
            --set githubConfigUrl="$GITHUB_CONFIG_URL" \
            --set githubConfigSecret.github_app_id="$GITHUB_APP_ID" \
            --set githubConfigSecret.github_app_installation_id="$GITHUB_APP_INSTALLATION_ID" \
            --set githubConfigSecret.github_app_private_key="$(cat $GITHUB_APP_PRIVATE_KEY_FILE)" \
            --set minRunners=0 \
            --set maxRunners=2 \
            --wait
    fi

    log "ARC deployed!"
    echo ""
    echo "Next steps:"
    echo "  1. Copy .github/workflows/poc-test.yaml to your repo"
    echo "  2. Push to trigger the workflow"
    echo "  3. Run: ./setup.sh watch"
}

cleanup() {
    log "Deleting minikube cluster..."
    minikube delete --profile="$PROFILE"
    log "Cleanup complete"
}

case "${1:-}" in
    setup)
        check_deps
        create_cluster
        load_sidecar_image
        deploy_arc
        ;;
    cleanup)
        cleanup
        ;;
    *)
        usage
        ;;
esac
