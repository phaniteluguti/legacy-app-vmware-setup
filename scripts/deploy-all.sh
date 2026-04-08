#!/usr/bin/env bash
# =============================================================================
# deploy-all.sh — One-click: Provision VMware VMs + Deploy Legacy Apps
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TF_DIR="$PROJECT_ROOT/terraform"
ANSIBLE_DIR="$PROJECT_ROOT/ansible"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()   { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ---------------------------------------------------------------------------
check_prerequisites() {
  log "Checking prerequisites..."
  local missing=()

  for cmd in terraform ansible-playbook ssh; do
    if ! command -v "$cmd" &>/dev/null; then
      missing+=("$cmd")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    error "Missing tools: ${missing[*]}"
    error "Install them before running this script."
    exit 1
  fi

  if [[ ! -f "$TF_DIR/terraform.tfvars" ]]; then
    error "terraform.tfvars not found. Copy terraform.tfvars.example and edit it:"
    error "  cp $TF_DIR/terraform.tfvars.example $TF_DIR/terraform.tfvars"
    exit 1
  fi

  if [[ ! -f "$ANSIBLE_DIR/group_vars/all.yml" ]]; then
    warn "group_vars/all.yml not found. Copying from example..."
    cp "$ANSIBLE_DIR/group_vars/all.yml.example" "$ANSIBLE_DIR/group_vars/all.yml"
    warn "EDIT $ANSIBLE_DIR/group_vars/all.yml with real passwords before deploying!"
  fi

  log "All prerequisites met."
}

# ---------------------------------------------------------------------------
provision_vms() {
  log "=== Phase 1: Provisioning VMware VMs with Terraform ==="
  cd "$TF_DIR"

  log "Initializing Terraform..."
  terraform init -input=false

  # Select workspace based on deploy_mode from tfvars
  local mode
  mode=$(grep 'deploy_mode' terraform.tfvars 2>/dev/null | sed 's/.*=\s*"\(.*\)"/\1/' || echo "linux")
  log "Selecting workspace: $mode"
  terraform workspace select -or-create "$mode"

  log "Planning infrastructure..."
  terraform plan -out=tfplan

  log "Applying infrastructure..."
  terraform apply -auto-approve tfplan

  log "VMs provisioned. Waiting 30s for SSH to be ready..."
  sleep 30

  cd "$PROJECT_ROOT"
}

# ---------------------------------------------------------------------------
deploy_apps() {
  log "=== Phase 2: Deploying Legacy Apps with Ansible ==="
  cd "$ANSIBLE_DIR"

  # Install required Ansible collections
  log "Installing Ansible Galaxy collections..."
  ansible-galaxy collection install community.postgresql community.mysql --force

  log "Running master playbook..."
  ansible-playbook -i inventory/hosts.ini site.yml -v

  cd "$PROJECT_ROOT"
}

# ---------------------------------------------------------------------------
verify_deployment() {
  log "=== Phase 3: Verifying Deployment ==="
  cd "$ANSIBLE_DIR"

  local mode
  mode=$(grep 'deploy_mode' "$TF_DIR/terraform.tfvars" 2>/dev/null | sed 's/.*=\s*"\(.*\)"/\1/' || echo "linux")

  case "$mode" in
    linux)
      ansible all -i inventory/hosts.ini -m shell -a "systemctl is-active petclinic || true"    --limit java_servers    2>/dev/null || true
      ansible all -i inventory/hosts.ini -m shell -a "systemctl is-active dotnet-app || true"   --limit dotnet_servers  2>/dev/null || true
      ansible all -i inventory/hosts.ini -m shell -a "systemctl is-active apache2 || true"      --limit php_servers     2>/dev/null || true
      log ""
      log "=== Deployment Summary ==="
      log "Java PetClinic:  http://$(terraform -chdir=$TF_DIR output -raw java_vm_ip):8080"
      log ".NET MVC App:    http://$(terraform -chdir=$TF_DIR output -raw dotnet_vm_ip)"
      log "PHP Laravel App: http://$(terraform -chdir=$TF_DIR output -raw php_vm_ip)"
      ;;
    windows)
      log ""
      log "=== Deployment Summary ==="
      log "Java PetClinic:  http://$(terraform -chdir=$TF_DIR output -raw java_vm_ip):8080"
      log ".NET IIS App:    http://$(terraform -chdir=$TF_DIR output -raw dotnet_vm_ip)"
      log "PHP Laravel App: http://$(terraform -chdir=$TF_DIR output -raw php_vm_ip)"
      ;;
    linux-3tier|windows-3tier)
      log ""
      log "=== 3-Tier Deployment Summary ==="
      log "Java Stack:"
      log "  Frontend:  $(terraform -chdir=$TF_DIR output -json java_3tier_ips 2>/dev/null | python3 -c 'import sys,json; d=json.load(sys.stdin); print(f"http://{d.get(\"frontend\",\"N/A\")}")' 2>/dev/null || echo 'N/A')"
      log "  App Server: $(terraform -chdir=$TF_DIR output -json java_3tier_ips 2>/dev/null | python3 -c 'import sys,json; d=json.load(sys.stdin); print(f"{d.get(\"appserver\",\"N/A\")}:9966")' 2>/dev/null || echo 'N/A')"
      log "  Database:   $(terraform -chdir=$TF_DIR output -json java_3tier_ips 2>/dev/null | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("database","N/A"))' 2>/dev/null || echo 'N/A')"
      log ".NET Stack:"
      log "  Frontend:  $(terraform -chdir=$TF_DIR output -json dotnet_3tier_ips 2>/dev/null | python3 -c 'import sys,json; d=json.load(sys.stdin); print(f"http://{d.get(\"frontend\",\"N/A\")}")' 2>/dev/null || echo 'N/A')"
      log "  App Server: $(terraform -chdir=$TF_DIR output -json dotnet_3tier_ips 2>/dev/null | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("appserver","N/A"))' 2>/dev/null || echo 'N/A')"
      log "  Database:   $(terraform -chdir=$TF_DIR output -json dotnet_3tier_ips 2>/dev/null | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("database","N/A"))' 2>/dev/null || echo 'N/A')"
      log "PHP Stack:"
      log "  Frontend:  $(terraform -chdir=$TF_DIR output -json php_3tier_ips 2>/dev/null | python3 -c 'import sys,json; d=json.load(sys.stdin); print(f"http://{d.get(\"frontend\",\"N/A\")}")' 2>/dev/null || echo 'N/A')"
      log "  App Server: $(terraform -chdir=$TF_DIR output -json php_3tier_ips 2>/dev/null | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("appserver","N/A"))' 2>/dev/null || echo 'N/A')"
      log "  Database:   $(terraform -chdir=$TF_DIR output -json php_3tier_ips 2>/dev/null | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("database","N/A"))' 2>/dev/null || echo 'N/A')"
      ;;
  esac

  log ""
  log "All VMs are ready for Azure Migrate discovery & assessment."
  log "=== Done ==="
}

# ---------------------------------------------------------------------------
usage() {
  echo "Usage: $0 [all|provision|deploy|verify|interactive]"
  echo ""
  echo "Commands:"
  echo "  all         Full pipeline: provision VMs + deploy apps + verify (default)"
  echo "  provision   Terraform only — create VMs on vSphere"
  echo "  deploy      Ansible only  — deploy apps to existing VMs"
  echo "  verify      Check service status and print URLs"
  echo "  interactive Launch guided wizard that asks for all inputs"
  exit 0
}

# ---------------------------------------------------------------------------
main() {
  local action="${1:-all}"

  case "$action" in
    all)
      check_prerequisites
      provision_vms
      deploy_apps
      verify_deployment
      ;;
    provision)
      check_prerequisites
      provision_vms
      ;;
    deploy)
      check_prerequisites
      deploy_apps
      ;;
    verify)
      verify_deployment
      ;;
    interactive)
      exec bash "$SCRIPT_DIR/setup-interactive.sh" "$@"
      ;;
    -h|--help)
      usage
      ;;
    *)
      error "Unknown action: $action"
      usage
      ;;
  esac
}

main "$@"
