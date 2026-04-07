#!/usr/bin/env bash
# =============================================================================
# setup-interactive.sh — Interactive wizard (Bash/WSL version)
# Collects inputs → generates terraform.tfvars + ansible vars → runs pipeline
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TF_DIR="$PROJECT_ROOT/terraform"
ANSIBLE_DIR="$PROJECT_ROOT/ansible"
TFVARS_FILE="$TF_DIR/terraform.tfvars"
ALLVARS_FILE="$ANSIBLE_DIR/group_vars/all.yml"

# Colors
C='\033[0;36m'; G='\033[0;32m'; Y='\033[1;33m'; R='\033[0;31m'; GR='\033[0;90m'; NC='\033[0m'

header()  { echo -e "\n${C}$(printf '=%.0s' {1..70})\n  $1\n$(printf '=%.0s' {1..70})${NC}\n"; }
step()    { echo -e "  ${G}>>${NC} $1"; }
warn()    { echo -e "  ${Y}[WARN]${NC} $1"; }
err()     { echo -e "  ${R}[ERROR]${NC} $1" >&2; }

# prompt "Label" "default" → sets REPLY
prompt() {
    local label="$1" default="${2:-}"
    if [[ -n "$default" ]]; then
        read -rp "  $label [$default]: " REPLY
        REPLY="${REPLY:-$default}"
    else
        while true; do
            read -rp "  $label: " REPLY
            [[ -n "$REPLY" ]] && break
            echo "    Value required." >&2
        done
    fi
}

# prompt_optional "Label" "default" → sets REPLY (allows blank, type - to clear)
prompt_optional() {
    local label="$1" default="${2:-}"
    if [[ -n "$default" ]]; then
        read -rp "  $label [$default] (type - to clear): " REPLY
        if [[ "$REPLY" == "-" ]]; then
            REPLY=""
        else
            REPLY="${REPLY:-$default}"
        fi
    else
        read -rp "  $label: " REPLY
    fi
}

prompt_secret() {
    local label="$1"
    while true; do
        read -srp "  $label: " REPLY; echo
        [[ -n "$REPLY" ]] && break
        echo "    Value required." >&2
    done
}

prompt_yn() {
    local label="$1" default="${2:-y}"
    local hint; [[ "$default" == "y" ]] && hint="Y/n" || hint="y/N"
    read -rp "  $label [$hint]: " REPLY
    REPLY="${REPLY:-$default}"
    [[ "${REPLY,,}" == "y" ]]
}

prompt_ip() {
    local label="$1" default="${2:-}"
    while true; do
        prompt "$label" "$default"
        if [[ "$REPLY" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            break
        fi
        echo "    Invalid IP format." >&2
    done
}

# ---------------------------------------------------------------------------
# Load previous values from saved config files (if they exist)
# ---------------------------------------------------------------------------
# Helper: extract value for a key from terraform.tfvars
tfval() { grep -m1 "^${1} " "$TFVARS_FILE" 2>/dev/null | sed 's/.*= *"\?\([^"]*\)"\?/\1/' || echo "$2"; }
# Helper: extract value for a key from ansible all.yml  
ymlval() { grep -m1 "^${1}:" "$ALLVARS_FILE" 2>/dev/null | sed 's/.*: *"\?\([^"]*\)"\?/\1/' || echo "$2"; }

load_previous() {
    # Initialize all defaults to hard-coded values
    PREV_VSPHERE_SERVER=""; PREV_VSPHERE_USER="administrator@vsphere.local"; PREV_VSPHERE_SSL="true"
    PREV_VSPHERE_DC="Datacenter1"; PREV_VSPHERE_CLUSTER="Cluster1"; PREV_VSPHERE_DS="datastore1"
    PREV_VSPHERE_NET="VM Network"; PREV_VSPHERE_FOLDER=""; PREV_VM_TEMPLATE="ubuntu-2204-template"
    PREV_VM_GW="192.168.1.1"; PREV_VM_MASK="24"; PREV_VM_DOMAIN="lab.local"
    PREV_VM_DNS="8.8.8.8,8.8.4.4"; PREV_SSH_USER="ubuntu"
    PREV_SSH_AUTH_METHOD="password"; PREV_SSH_KEY="\$HOME/.ssh/id_rsa"
    PREV_JAVA_IP="192.168.1.101"; PREV_JAVA_CPU="2"; PREV_JAVA_MEM="4096"; PREV_JAVA_DISK="40"
    PREV_DOTNET_IP="192.168.1.102"; PREV_DOTNET_CPU="2"; PREV_DOTNET_MEM="4096"; PREV_DOTNET_DISK="40"
    PREV_PHP_IP="192.168.1.103"; PREV_PHP_CPU="2"; PREV_PHP_MEM="2048"; PREV_PHP_DISK="30"
    PREV_PETCLINIC_REPO="https://github.com/oreakinodidi98/AKS_APP_Mod_Demo"
    PREV_PETCLINIC_BRANCH="main"; PREV_JAVA_VER="17"
    PREV_DOTNET_SDK="6.0"; PREV_DOTNET_REPO="https://github.com/dotnet/eShop.git"; PREV_DOTNET_BRANCH="main"
    PREV_PHP_VER="8.1"; PREV_PHP_REPO="https://github.com/laravel/laravel.git"; PREV_PHP_BRANCH="10.x"
    PREV_AZ_AGENT="false"

    if [[ -f "$TFVARS_FILE" ]]; then
        step "Found previous config: terraform.tfvars — loading as defaults"
        PREV_VSPHERE_SERVER="$(tfval vsphere_server "")"
        PREV_VSPHERE_USER="$(tfval vsphere_user "administrator@vsphere.local")"
        PREV_VSPHERE_SSL="$(tfval vsphere_allow_unverified_ssl "true")"
        PREV_VSPHERE_DC="$(tfval vsphere_datacenter "Datacenter1")"
        PREV_VSPHERE_CLUSTER="$(tfval vsphere_cluster "Cluster1")"
        PREV_VSPHERE_DS="$(tfval vsphere_datastore "datastore1")"
        PREV_VSPHERE_NET="$(tfval vsphere_network "VM Network")"
        PREV_VSPHERE_FOLDER="$(tfval vsphere_folder "")"
        PREV_VM_TEMPLATE="$(tfval vm_template_name "ubuntu-2204-template")"
        PREV_VM_GW="$(tfval vm_gateway "192.168.1.1")"
        PREV_VM_MASK="$(tfval vm_netmask "24")"
        PREV_VM_DOMAIN="$(tfval vm_domain "lab.local")"
        local raw_dns; raw_dns=$(grep -m1 "^vm_dns_servers" "$TFVARS_FILE" 2>/dev/null | sed 's/.*\[\(.*\)\]/\1/;s/"//g;s/ //g' || echo "")
        [[ -n "$raw_dns" ]] && PREV_VM_DNS="$raw_dns"
        PREV_SSH_USER="$(tfval vm_ssh_user "ubuntu")"
        PREV_SSH_AUTH_METHOD="$(tfval vm_ssh_auth_method "password")"
        PREV_SSH_KEY="$(tfval vm_ssh_private_key_path "\$HOME/.ssh/id_rsa")"
        PREV_JAVA_IP="$(tfval java_vm_ip "192.168.1.101")"
        PREV_JAVA_CPU="$(tfval java_vm_cpus "2")"
        PREV_JAVA_MEM="$(tfval java_vm_memory "4096")"
        PREV_JAVA_DISK="$(tfval java_vm_disk "40")"
        PREV_DOTNET_IP="$(tfval dotnet_vm_ip "192.168.1.102")"
        PREV_DOTNET_CPU="$(tfval dotnet_vm_cpus "2")"
        PREV_DOTNET_MEM="$(tfval dotnet_vm_memory "4096")"
        PREV_DOTNET_DISK="$(tfval dotnet_vm_disk "40")"
        PREV_PHP_IP="$(tfval php_vm_ip "192.168.1.103")"
        PREV_PHP_CPU="$(tfval php_vm_cpus "2")"
        PREV_PHP_MEM="$(tfval php_vm_memory "2048")"
        PREV_PHP_DISK="$(tfval php_vm_disk "30")"
    fi

    if [[ -f "$ALLVARS_FILE" ]]; then
        step "Found previous config: group_vars/all.yml — loading as defaults"
        PREV_PETCLINIC_REPO="$(ymlval petclinic_repo "https://github.com/oreakinodidi98/AKS_APP_Mod_Demo")"
        PREV_PETCLINIC_BRANCH="$(ymlval petclinic_branch "main")"
        PREV_JAVA_VER="$(ymlval java_version "17")"
        PREV_DOTNET_SDK="$(ymlval dotnet_sdk_version "6.0")"
        PREV_DOTNET_REPO="$(ymlval dotnet_app_repo "https://github.com/dotnet/eShop.git")"
        PREV_DOTNET_BRANCH="$(ymlval dotnet_app_branch "main")"
        PREV_PHP_VER="$(ymlval php_version "8.1")"
        PREV_PHP_REPO="$(ymlval php_app_repo "https://github.com/laravel/laravel.git")"
        PREV_PHP_BRANCH="$(ymlval php_app_branch "10.x")"
        PREV_AZ_AGENT="$(ymlval install_azure_migrate_agent "false")"
    fi
}

# ---------------------------------------------------------------------------
check_prerequisites() {
    header "Checking Prerequisites"
    local missing=()
    for cmd in terraform ansible-playbook ssh sshpass; do
        if command -v "$cmd" &>/dev/null; then
            step "$cmd ... found"
        else
            echo -e "  ${R}[MISS] $cmd${NC}"
            missing+=("$cmd")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        err "Missing: ${missing[*]}. Install and re-run."
        echo -e "  ${GR}Hint: sudo apt install -y sshpass  (for password-based SSH)${NC}"
        exit 1
    fi
    step "All prerequisites met."
}

# ---------------------------------------------------------------------------
collect_vcenter() {
    header "Step 1/6 — vCenter Connection"
    prompt "vCenter Server FQDN or IP" "$PREV_VSPHERE_SERVER"; VSPHERE_SERVER="$REPLY"
    prompt "vCenter Username" "$PREV_VSPHERE_USER"; VSPHERE_USER="$REPLY"
    prompt_secret "vCenter Password"; VSPHERE_PASSWORD="$REPLY"
    prompt_yn "Allow unverified SSL?" "${PREV_VSPHERE_SSL:0:1}" && VSPHERE_SSL="true" || VSPHERE_SSL="false"
}

collect_infra() {
    header "Step 2/6 — vSphere Infrastructure"
    echo -e "  ${GR}Names must match your vCenter inventory exactly.${NC}"
    prompt "Datacenter name" "$PREV_VSPHERE_DC"; VSPHERE_DC="$REPLY"
    prompt "Compute Cluster name" "$PREV_VSPHERE_CLUSTER"; VSPHERE_CLUSTER="$REPLY"
    prompt "Datastore name" "$PREV_VSPHERE_DS"; VSPHERE_DS="$REPLY"
    prompt "Network / Port Group" "$PREV_VSPHERE_NET"; VSPHERE_NET="$REPLY"
    prompt_optional "VM Folder (blank for root)" "$PREV_VSPHERE_FOLDER"; VSPHERE_FOLDER="$REPLY"
    prompt "Ubuntu 22.04 Template name" "$PREV_VM_TEMPLATE"; VM_TEMPLATE="$REPLY"
}

collect_network() {
    header "Step 3/6 — VM Network Settings"
    prompt_ip "Default Gateway IP" "$PREV_VM_GW"; VM_GW="$REPLY"
    prompt "Subnet mask (CIDR bits)" "$PREV_VM_MASK"; VM_MASK="$REPLY"
    prompt "Domain suffix" "$PREV_VM_DOMAIN"; VM_DOMAIN="$REPLY"
    prompt "DNS Servers (comma-sep)" "$PREV_VM_DNS"; VM_DNS="$REPLY"
    prompt "SSH username in template" "$PREV_SSH_USER"; SSH_USER="$REPLY"

    echo ""
    echo -e "  ${Y}How will Ansible connect to the VMs?${NC}"
    echo -e "    ${G}1)${NC} SSH key (public key baked into template)"
    echo -e "    ${G}2)${NC} SSH password (simpler — no key needed in template)"
    local default_auth; [[ "$PREV_SSH_AUTH_METHOD" == "key" ]] && default_auth="1" || default_auth="2"
    read -rp "  Choose [1/2] (default: $default_auth): " AUTH_CHOICE
    AUTH_CHOICE="${AUTH_CHOICE:-$default_auth}"

    if [[ "$AUTH_CHOICE" == "1" ]]; then
        SSH_AUTH_METHOD="key"
        prompt "SSH private key path" "$PREV_SSH_KEY"; SSH_KEY="$REPLY"
        if [[ ! -f "$SSH_KEY" ]]; then
            warn "Key not found: $SSH_KEY"
            prompt_yn "Continue anyway?" || exit 1
        fi
        SSH_PASSWORD=""
    else
        SSH_AUTH_METHOD="password"
        prompt_secret "SSH password for user '$SSH_USER'"; SSH_PASSWORD="$REPLY"
        SSH_KEY=""
    fi
}

collect_vms() {
    header "Step 4/6 — VM Sizing & IP Addresses"
    echo -e "  ${GR}Static IPs on the same subnet as gateway $VM_GW${NC}\n"

    echo -e "  ${Y}--- Java VM (PetClinic + PostgreSQL) ---${NC}"
    prompt_ip "  IP" "$PREV_JAVA_IP"; JAVA_IP="$REPLY"
    prompt "  CPUs" "$PREV_JAVA_CPU"; JAVA_CPU="$REPLY"
    prompt "  Memory MB" "$PREV_JAVA_MEM"; JAVA_MEM="$REPLY"
    prompt "  Disk GB" "$PREV_JAVA_DISK"; JAVA_DISK="$REPLY"

    echo -e "\n  ${Y}--- .NET VM (ASP.NET + SQL Server) ---${NC}"
    prompt_ip "  IP" "$PREV_DOTNET_IP"; DOTNET_IP="$REPLY"
    prompt "  CPUs" "$PREV_DOTNET_CPU"; DOTNET_CPU="$REPLY"
    prompt "  Memory MB" "$PREV_DOTNET_MEM"; DOTNET_MEM="$REPLY"
    prompt "  Disk GB" "$PREV_DOTNET_DISK"; DOTNET_DISK="$REPLY"

    echo -e "\n  ${Y}--- PHP VM (Laravel + MySQL) ---${NC}"
    prompt_ip "  IP" "$PREV_PHP_IP"; PHP_IP="$REPLY"
    prompt "  CPUs" "$PREV_PHP_CPU"; PHP_CPU="$REPLY"
    prompt "  Memory MB" "$PREV_PHP_MEM"; PHP_MEM="$REPLY"
    prompt "  Disk GB" "$PREV_PHP_DISK"; PHP_DISK="$REPLY"
}

collect_apps() {
    header "Step 5/6 — Application & Database Configuration"

    echo -e "  ${Y}--- Java / PetClinic ---${NC}"
    prompt "  Git repo" "$PREV_PETCLINIC_REPO"; PETCLINIC_REPO="$REPLY"
    prompt "  Branch" "$PREV_PETCLINIC_BRANCH"; PETCLINIC_BRANCH="$REPLY"
    prompt "  JDK version" "$PREV_JAVA_VER"; JAVA_VER="$REPLY"
    prompt_secret "  PostgreSQL password"; PG_PASS="$REPLY"

    echo -e "\n  ${Y}--- .NET / ASP.NET Core ---${NC}"
    prompt "  .NET SDK version" "$PREV_DOTNET_SDK"; DOTNET_SDK="$REPLY"
    prompt "  Git repo" "$PREV_DOTNET_REPO"; DOTNET_REPO="$REPLY"
    prompt "  Branch" "$PREV_DOTNET_BRANCH"; DOTNET_BRANCH="$REPLY"
    prompt_secret "  SQL Server SA password (8+ chars, complexity)"; MSSQL_PASS="$REPLY"

    echo -e "\n  ${Y}--- PHP / Laravel ---${NC}"
    prompt "  PHP version" "$PREV_PHP_VER"; PHP_VER="$REPLY"
    prompt "  Git repo" "$PREV_PHP_REPO"; PHP_REPO="$REPLY"
    prompt "  Branch" "$PREV_PHP_BRANCH"; PHP_BRANCH="$REPLY"
    prompt_secret "  MySQL root password"; MYSQL_ROOT="$REPLY"
    prompt_secret "  MySQL app user password"; MYSQL_APP="$REPLY"
}

collect_migrate() {
    header "Step 6/6 — Azure Migrate Options"
    local default_yn; [[ "$PREV_AZ_AGENT" == "true" ]] && default_yn="y" || default_yn="n"
    prompt_yn "Install Azure Migrate Dependency Agent on VMs?" "$default_yn" && AZ_AGENT="true" || AZ_AGENT="false"
}

# ---------------------------------------------------------------------------
show_summary() {
    header "Configuration Summary"
    echo -e "  vCenter:    $VSPHERE_SERVER"
    echo -e "  Datacenter: $VSPHERE_DC   Cluster: $VSPHERE_CLUSTER"
    echo -e "  Template:   $VM_TEMPLATE"
    echo -e "  Network:    $VSPHERE_NET  Gateway: $VM_GW/$VM_MASK\n"
    echo -e "  VMs:"
    echo -e "    Java  $JAVA_IP   ${JAVA_CPU}CPU / ${JAVA_MEM}MB / ${JAVA_DISK}GB"
    echo -e "    .NET  $DOTNET_IP ${DOTNET_CPU}CPU / ${DOTNET_MEM}MB / ${DOTNET_DISK}GB"
    echo -e "    PHP   $PHP_IP    ${PHP_CPU}CPU / ${PHP_MEM}MB / ${PHP_DISK}GB\n"
    echo -e "  Apps:"
    echo -e "    Java:  $PETCLINIC_REPO"
    echo -e "    .NET:  $DOTNET_REPO"
    echo -e "    PHP:   $PHP_REPO"
}

# ---------------------------------------------------------------------------
write_tfvars() {
    step "Generating terraform/terraform.tfvars ..."
    local dns_arr
    dns_arr=$(echo "$VM_DNS" | tr ',' '\n' | sed 's/^ *//;s/ *$//' | awk '{printf "\"%s\", ", $0}' | sed 's/, $//')

    cat > "$TF_DIR/terraform.tfvars" <<EOF
# Auto-generated by setup-interactive.sh on $(date '+%Y-%m-%d %H:%M:%S')

vsphere_server               = "$VSPHERE_SERVER"
vsphere_user                 = "$VSPHERE_USER"
vsphere_password             = "$VSPHERE_PASSWORD"
vsphere_allow_unverified_ssl = $VSPHERE_SSL

vsphere_datacenter = "$VSPHERE_DC"
vsphere_cluster    = "$VSPHERE_CLUSTER"
vsphere_datastore  = "$VSPHERE_DS"
vsphere_network    = "$VSPHERE_NET"
vsphere_folder     = "$VSPHERE_FOLDER"
vm_template_name   = "$VM_TEMPLATE"

vm_domain              = "$VM_DOMAIN"
vm_gateway             = "$VM_GW"
vm_netmask             = $VM_MASK
vm_dns_servers         = [$dns_arr]
vm_ssh_user            = "$SSH_USER"
vm_ssh_auth_method     = "$SSH_AUTH_METHOD"
vm_ssh_private_key_path = "$SSH_KEY"
vm_ssh_password        = "$SSH_PASSWORD"

java_vm_ip     = "$JAVA_IP"
java_vm_cpus   = $JAVA_CPU
java_vm_memory = $JAVA_MEM
java_vm_disk   = $JAVA_DISK

dotnet_vm_ip     = "$DOTNET_IP"
dotnet_vm_cpus   = $DOTNET_CPU
dotnet_vm_memory = $DOTNET_MEM
dotnet_vm_disk   = $DOTNET_DISK

php_vm_ip     = "$PHP_IP"
php_vm_cpus   = $PHP_CPU
php_vm_memory = $PHP_MEM
php_vm_disk   = $PHP_DISK
EOF
    step "Created: terraform/terraform.tfvars"
}

write_ansible_vars() {
    step "Generating ansible/group_vars/all.yml ..."
    mkdir -p "$ANSIBLE_DIR/group_vars"

    cat > "$ANSIBLE_DIR/group_vars/all.yml" <<EOF
# Auto-generated by setup-interactive.sh on $(date '+%Y-%m-%d %H:%M:%S')

ansible_become: true
ansible_python_interpreter: /usr/bin/python3

petclinic_repo: "$PETCLINIC_REPO"
petclinic_branch: "$PETCLINIC_BRANCH"
java_version: "$JAVA_VER"
petclinic_app_port: 8080

postgres_version: "15"
postgres_db: "petclinic"
postgres_user: "petclinic"
postgres_password: "$PG_PASS"

dotnet_sdk_version: "$DOTNET_SDK"
dotnet_app_repo: "$DOTNET_REPO"
dotnet_app_branch: "$DOTNET_BRANCH"
dotnet_app_port: 5000

mssql_edition: "express"
mssql_sa_password: "$MSSQL_PASS"
mssql_db_name: "eShopDb"

php_version: "$PHP_VER"
php_app_repo: "$PHP_REPO"
php_app_branch: "$PHP_BRANCH"
php_app_port: 80

mysql_root_password: "$MYSQL_ROOT"
mysql_db_name: "laravel_app"
mysql_db_user: "laravel"
mysql_db_password: "$MYSQL_APP"

install_azure_migrate_agent: $AZ_AGENT
EOF
    step "Created: ansible/group_vars/all.yml"
}

write_inventory() {
    step "Generating ansible/inventory/hosts.ini ..."
    mkdir -p "$ANSIBLE_DIR/inventory"

    # Build the auth portion of each inventory line
    if [[ "$SSH_AUTH_METHOD" == "password" ]]; then
        AUTH_LINE="ansible_ssh_pass=$SSH_PASSWORD ansible_become_pass=$SSH_PASSWORD ansible_ssh_common_args='-o StrictHostKeyChecking=no'"
    else
        AUTH_LINE="ansible_ssh_private_key_file=$SSH_KEY"
    fi

    cat > "$ANSIBLE_DIR/inventory/hosts.ini" <<EOF
# Auto-generated by setup-interactive.sh
[java_servers]
$JAVA_IP ansible_user=$SSH_USER $AUTH_LINE

[dotnet_servers]
$DOTNET_IP ansible_user=$SSH_USER $AUTH_LINE

[php_servers]
$PHP_IP ansible_user=$SSH_USER $AUTH_LINE

[legacy_apps:children]
java_servers
dotnet_servers
php_servers
EOF
    step "Created: ansible/inventory/hosts.ini"
}

# ---------------------------------------------------------------------------
run_terraform() {
    header "Phase 1 — Provisioning VMs on vSphere (Terraform)"
    pushd "$TF_DIR" > /dev/null

    step "terraform init ..."
    terraform init -input=false

    step "terraform plan ..."
    terraform plan -out=tfplan

    step "terraform apply ..."
    terraform apply -auto-approve tfplan

    step "VMs created. Waiting 60s for SSH readiness..."
    sleep 60

    popd > /dev/null
}

run_ansible() {
    header "Phase 2 — Deploying Applications (Ansible)"
    pushd "$ANSIBLE_DIR" > /dev/null

    # Fix directory permissions so ansible.cfg is loaded
    chmod 755 "$ANSIBLE_DIR" 2>/dev/null || true
    export ANSIBLE_CONFIG="$ANSIBLE_DIR/ansible.cfg"

    step "Installing Ansible Galaxy collections..."
    ansible-galaxy collection install community.postgresql community.mysql community.general --force

    local max_retries=3
    local attempt=1
    local retry_file=""

    while [[ $attempt -le $max_retries ]]; do
        if [[ $attempt -eq 1 && -z "$retry_file" ]]; then
            step "Running master playbook (attempt $attempt/$max_retries)..."
            ansible-playbook -i inventory/hosts.ini site.yml -v && break
        else
            step "Retrying failed tasks (attempt $attempt/$max_retries)..."
            ansible-playbook -i inventory/hosts.ini site.yml -v --limit @site.retry && break
        fi

        if [[ -f "site.retry" ]]; then
            retry_file="site.retry"
            warn "Attempt $attempt failed. Hosts with failures: $(cat site.retry)"
        fi

        if [[ $attempt -lt $max_retries ]]; then
            step "Waiting 30s before retry..."
            sleep 30
        fi
        ((attempt++))
    done

    if [[ $attempt -gt $max_retries ]]; then
        err "Ansible failed after $max_retries attempts."
        echo -e "  ${Y}To resume later, run:${NC}"
        echo -e "    ${GR}cd ansible${NC}"
        if [[ -f "site.retry" ]]; then
            echo -e "    ${GR}ansible-playbook -i inventory/hosts.ini site.yml -v --limit @site.retry${NC}"
        else
            echo -e "    ${GR}ansible-playbook -i inventory/hosts.ini site.yml -v${NC}"
        fi
        popd > /dev/null
        return 1
    fi

    popd > /dev/null
}

run_verify() {
    header "Phase 3 — Verification"
    echo ""
    for pair in "Java PetClinic|$JAVA_IP|8080" ".NET MVC App|$DOTNET_IP|80" "PHP Laravel|$PHP_IP|80"; do
        IFS='|' read -r name ip port <<< "$pair"
        if timeout 3 bash -c "echo >/dev/tcp/$ip/$port" 2>/dev/null; then
            echo -e "    ${G}[OK]${NC}   $name  http://$ip:$port"
        else
            echo -e "    ${Y}[WAIT]${NC} $name  http://$ip:$port — may still be starting"
        fi
    done

    header "Deployment Complete!"
    echo -e "  Access your apps:"
    echo -e "    ${C}Java PetClinic:${NC}  http://$JAVA_IP:8080"
    echo -e "    ${C}.NET MVC App:${NC}    http://$DOTNET_IP"
    echo -e "    ${C}PHP Laravel:${NC}     http://$PHP_IP"
    echo ""
    echo -e "  ${G}All VMs ready for Azure Migrate discovery.${NC}"
    echo -e "  ${G}Point appliance at vCenter: $VSPHERE_SERVER${NC}"
    echo ""
}

# ---------------------------------------------------------------------------
run_destroy() {
    header "Destroying VMs (Terraform Destroy)"
    pushd "$TF_DIR" > /dev/null

    if [[ ! -f "terraform.tfstate" ]] && [[ ! -f ".terraform/terraform.tfstate" ]]; then
        warn "No Terraform state found. Nothing to destroy."
        warn "If VMs were created, delete them manually in vCenter."
        popd > /dev/null
        return
    fi

    step "terraform init ..."
    terraform init -input=false

    step "terraform destroy ..."
    terraform destroy -auto-approve

    step "VMs destroyed successfully."
    popd > /dev/null
}

run_ansible_resume() {
    header "Phase 2 — Resuming Ansible (failed hosts only)"
    pushd "$ANSIBLE_DIR" > /dev/null

    # Fix directory permissions so ansible.cfg is loaded
    chmod 755 "$ANSIBLE_DIR" 2>/dev/null || true
    export ANSIBLE_CONFIG="$ANSIBLE_DIR/ansible.cfg"

    local retry_file="site.retry"
    if [[ -f "$retry_file" ]]; then
        step "Found retry file with hosts: $(cat "$retry_file")"
        step "Resuming playbook for failed hosts..."
        ansible-playbook -i inventory/hosts.ini site.yml -v --limit "@$retry_file"
    else
        warn "No retry file found. Running full playbook..."
        ansible-playbook -i inventory/hosts.ini site.yml -v
    fi

    popd > /dev/null
}

# ---------------------------------------------------------------------------
main() {
    # Handle --destroy flag for quick cleanup
    if [[ "${1:-}" == "--destroy" || "${1:-}" == "destroy" ]]; then
        echo ""
        echo -e "  ${R}================================================================${NC}"
        echo -e "  ${R}     Terraform Destroy — Remove All VMs${NC}"
        echo -e "  ${R}================================================================${NC}"
        echo ""
        run_destroy
        exit 0
    fi

    # Handle --resume flag to retry failed Ansible hosts
    if [[ "${1:-}" == "--resume" || "${1:-}" == "resume" ]]; then
        echo ""
        echo -e "  ${C}================================================================${NC}"
        echo -e "  ${C}     Resume Ansible — Retry Failed Hosts${NC}"
        echo -e "  ${C}================================================================${NC}"
        echo ""
        check_prerequisites
        run_ansible_resume
        run_verify
        exit 0
    fi

    echo ""
    echo -e "  ${C}================================================================${NC}"
    echo -e "  ${C}     Legacy App Lab — Interactive Setup Wizard${NC}"
    echo -e "  ${C}     VMware VM Provisioning + App Deployment${NC}"
    echo -e "  ${C}     For Azure Migrate Assessment${NC}"
    echo -e "  ${C}================================================================${NC}"
    echo ""

    check_prerequisites
    load_previous

    collect_vcenter
    collect_infra
    collect_network
    collect_vms
    collect_apps
    collect_migrate

    show_summary

    echo ""
    echo -e "  ${Y}Would you like to save these values to config files?${NC}"
    echo -e "    ${G}1)${NC} Save to terraform.tfvars + ansible vars + inventory"
    echo -e "    ${G}2)${NC} Discard and exit (nothing is written)"
    read -rp "  Choice [1]: " save_choice
    save_choice="${save_choice:-1}"

    if [[ "$save_choice" != "1" ]]; then
        warn "Aborted. No files were written."
        exit 0
    fi

    header "Saving Configuration Files"
    write_tfvars
    write_ansible_vars
    write_inventory

    echo ""
    echo -e "  ${G}Files saved successfully:${NC}"
    echo -e "    ${C}terraform/terraform.tfvars${NC}"
    echo -e "    ${C}ansible/group_vars/all.yml${NC}"
    echo -e "    ${C}ansible/inventory/hosts.ini${NC}"

    echo ""
    echo -e "  ${Y}What would you like to do next?${NC}"
    echo -e "    ${G}1)${NC} Run full pipeline (Terraform + Ansible + Verify)"
    echo -e "    ${G}2)${NC} Stop here — I'll run Terraform & Ansible myself later"
    echo -e "    ${G}3)${NC} Terraform only (provision VMs)"
    echo -e "    ${G}4)${NC} Ansible only (deploy to existing VMs)"
    echo -e "    ${G}5)${NC} Resume Ansible (retry failed hosts only)"
    echo -e "    ${G}6)${NC} ${R}Destroy all VMs${NC} (terraform destroy)"
    read -rp "  Choice [2]: " choice
    choice="${choice:-2}"

    case "$choice" in
        1) run_terraform; run_ansible; run_verify ;;
        2) step "Config files saved. Run manually when ready:"
           echo -e "    ${GR}cd terraform && terraform init && terraform apply${NC}"
           echo -e "    ${GR}cd ansible && ansible-playbook -i inventory/hosts.ini site.yml${NC}" ;;
        3) run_terraform ;;
        4) run_ansible; run_verify ;;
        5) run_ansible_resume; run_verify ;;
        6) run_destroy ;;
        *) err "Invalid choice"; exit 1 ;;
    esac
}

main "$@"
