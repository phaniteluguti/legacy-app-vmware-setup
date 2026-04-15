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

# Global deploy state
DEPLOY_MODES=()
DEPLOY_JAVA="true"
DEPLOY_DOTNET="true"
DEPLOY_PHP="true"
QUICK_MODE=false

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
ymlval() { grep -m1 "^${1}:" "$ALLVARS_FILE" 2>/dev/null | sed "s/^${1}: *\"\{0,1\}\([^\"]*\)\"\{0,1\}/\1/" || echo "$2"; }

load_previous() {
    # Initialize all defaults to hard-coded values
    PREV_DEPLOY_MODE="linux"
    PREV_APP_SELECTION="all"; PREV_OS_CHOICE="linux"; PREV_ARCH_CHOICE="single"
    PREV_DEPLOY_JAVA="true"; PREV_DEPLOY_DOTNET="true"; PREV_DEPLOY_PHP="true"
    PREV_VSPHERE_SERVER=""; PREV_VSPHERE_USER="administrator@vsphere.local"; PREV_VSPHERE_SSL="true"
    PREV_VSPHERE_DC="Datacenter1"; PREV_VSPHERE_CLUSTER="Cluster1"; PREV_VSPHERE_DS="datastore1"
    PREV_VSPHERE_NET="VM Network"; PREV_VSPHERE_FOLDER=""; PREV_VM_TEMPLATE="ubuntu-2204-template"
    PREV_VM_GW="192.168.1.1"; PREV_VM_MASK="24"; PREV_VM_DOMAIN="lab.local"
    PREV_VM_DNS="8.8.8.8,8.8.4.4"; PREV_SSH_USER="ubuntu"
    PREV_SSH_AUTH_METHOD="password"; PREV_SSH_KEY="\$HOME/.ssh/id_rsa"
    PREV_JAVA_IP="192.168.1.101"; PREV_JAVA_CPU="2"; PREV_JAVA_MEM="4096"; PREV_JAVA_DISK="40"
    PREV_DOTNET_IP="192.168.1.102"; PREV_DOTNET_CPU="2"; PREV_DOTNET_MEM="4096"; PREV_DOTNET_DISK="40"
    PREV_PHP_IP="192.168.1.103"; PREV_PHP_CPU="2"; PREV_PHP_MEM="2048"; PREV_PHP_DISK="30"
    # Single-VM hostname defaults
    PREV_JAVA_HOSTNAME="legacy-java-vm"; PREV_DOTNET_HOSTNAME="legacy-dotnet-vm"; PREV_PHP_HOSTNAME="legacy-php-vm"
    PREV_WIN_TEMPLATE="windows-2019-template"
    PREV_PETCLINIC_REPO="https://github.com/oreakinodidi98/AKS_APP_Mod_Demo"
    PREV_PETCLINIC_BRANCH="main"; PREV_JAVA_VER="17"
    PREV_DOTNET_SDK="6.0"; PREV_DOTNET_REPO="https://github.com/dotnet/eShop.git"; PREV_DOTNET_BRANCH="main"
    PREV_PHP_VER="8.1"; PREV_PHP_REPO="https://github.com/laravel/laravel.git"; PREV_PHP_BRANCH="10.x"
    PREV_AZ_AGENT="false"
    # 3-Tier sizing defaults
    PREV_FE_CPU="1"; PREV_FE_MEM="2048"; PREV_FE_DISK="20"
    PREV_APP_CPU="2"; PREV_APP_MEM="4096"; PREV_APP_DISK="40"
    PREV_DB_CPU="2"; PREV_DB_MEM="4096"; PREV_DB_DISK="60"
    # 3-Tier IP defaults
    PREV_JAVA_FE_IP="10.1.2.20"; PREV_JAVA_APP_IP="10.1.2.21"; PREV_JAVA_DB_IP="10.1.2.22"
    PREV_DOTNET_FE_IP="10.1.2.23"; PREV_DOTNET_APP_IP="10.1.2.24"; PREV_DOTNET_DB_IP="10.1.2.25"
    PREV_PHP_FE_IP="10.1.2.26"; PREV_PHP_APP_IP="10.1.2.27"; PREV_PHP_DB_IP="10.1.2.28"
    # 3-Tier hostname defaults
    PREV_JAVA_FE_HOSTNAME="lin-java-fe"; PREV_JAVA_APP_HOSTNAME="lin-java-app"; PREV_JAVA_DB_HOSTNAME="lin-java-db"
    PREV_DOTNET_FE_HOSTNAME="lin-dotnet-fe"; PREV_DOTNET_APP_HOSTNAME="lin-dotnet-app"; PREV_DOTNET_DB_HOSTNAME="lin-dotnet-db"
    PREV_PHP_FE_HOSTNAME="lin-php-fe"; PREV_PHP_APP_HOSTNAME="lin-php-app"; PREV_PHP_DB_HOSTNAME="lin-php-db"

    if [[ -f "$TFVARS_FILE" ]]; then
        step "Found previous config: terraform.tfvars — loading as defaults"
        PREV_DEPLOY_MODE="$(tfval deploy_mode "linux")"
        PREV_DEPLOY_JAVA="$(tfval deploy_java "true")"
        PREV_DEPLOY_DOTNET="$(tfval deploy_dotnet "true")"
        PREV_DEPLOY_PHP="$(tfval deploy_php "true")"
        # Parse wizard choices from comment header
        local wiz_line; wiz_line=$(grep -m1 "^# wizard_choices:" "$TFVARS_FILE" 2>/dev/null || echo "")
        if [[ -n "$wiz_line" ]]; then
            PREV_APP_SELECTION=$(echo "$wiz_line" | sed 's/.*app=\([^ ]*\).*/\1/')
            PREV_OS_CHOICE=$(echo "$wiz_line" | sed 's/.*os=\([^ ]*\).*/\1/')
            PREV_ARCH_CHOICE=$(echo "$wiz_line" | sed 's/.*arch=\([^ ]*\).*/\1/')
        else
            # Derive from deploy_mode for backward compatibility
            case "$PREV_DEPLOY_MODE" in
                linux)          PREV_OS_CHOICE="linux";   PREV_ARCH_CHOICE="single" ;;
                windows)        PREV_OS_CHOICE="windows"; PREV_ARCH_CHOICE="single" ;;
                linux-3tier)    PREV_OS_CHOICE="linux";   PREV_ARCH_CHOICE="3tier" ;;
                windows-3tier)  PREV_OS_CHOICE="windows"; PREV_ARCH_CHOICE="3tier" ;;
            esac
            if [[ "$PREV_DEPLOY_JAVA" == "true" && "$PREV_DEPLOY_DOTNET" == "true" && "$PREV_DEPLOY_PHP" == "true" ]]; then
                PREV_APP_SELECTION="all"
            elif [[ "$PREV_DEPLOY_JAVA" == "true" ]]; then
                PREV_APP_SELECTION="java"
            elif [[ "$PREV_DEPLOY_DOTNET" == "true" ]]; then
                PREV_APP_SELECTION="dotnet"
            elif [[ "$PREV_DEPLOY_PHP" == "true" ]]; then
                PREV_APP_SELECTION="php"
            fi
        fi
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
        PREV_JAVA_HOSTNAME="$(tfval java_vm_hostname "legacy-java-vm")"
        PREV_DOTNET_IP="$(tfval dotnet_vm_ip "192.168.1.102")"
        PREV_DOTNET_CPU="$(tfval dotnet_vm_cpus "2")"
        PREV_DOTNET_MEM="$(tfval dotnet_vm_memory "4096")"
        PREV_DOTNET_DISK="$(tfval dotnet_vm_disk "40")"
        PREV_DOTNET_HOSTNAME="$(tfval dotnet_vm_hostname "legacy-dotnet-vm")"
        PREV_PHP_IP="$(tfval php_vm_ip "192.168.1.103")"
        PREV_PHP_CPU="$(tfval php_vm_cpus "2")"
        PREV_PHP_MEM="$(tfval php_vm_memory "2048")"
        PREV_PHP_DISK="$(tfval php_vm_disk "30")"
        PREV_PHP_HOSTNAME="$(tfval php_vm_hostname "legacy-php-vm")"
        PREV_WIN_TEMPLATE="$(tfval win_template_name "windows-2019-template")"
        # 3-Tier VM sizing
        PREV_FE_CPU="$(tfval fe_cpus "1")"
        PREV_FE_MEM="$(tfval fe_memory "2048")"
        PREV_FE_DISK="$(tfval fe_disk "20")"
        PREV_APP_CPU="$(tfval app_cpus "2")"
        PREV_APP_MEM="$(tfval app_memory "4096")"
        PREV_APP_DISK="$(tfval app_disk "40")"
        PREV_DB_CPU="$(tfval db_cpus "2")"
        PREV_DB_MEM="$(tfval db_memory "4096")"
        PREV_DB_DISK="$(tfval db_disk "60")"
        # 3-Tier IPs (Linux)
        PREV_JAVA_FE_IP="$(tfval java_fe_ip "10.1.2.20")"
        PREV_JAVA_APP_IP="$(tfval java_app_ip "10.1.2.21")"
        PREV_JAVA_DB_IP="$(tfval java_db_ip "10.1.2.22")"
        PREV_DOTNET_FE_IP="$(tfval dotnet_fe_ip "10.1.2.23")"
        PREV_DOTNET_APP_IP="$(tfval dotnet_app_ip "10.1.2.24")"
        PREV_DOTNET_DB_IP="$(tfval dotnet_db_ip "10.1.2.25")"
        PREV_PHP_FE_IP="$(tfval php_fe_ip "10.1.2.26")"
        PREV_PHP_APP_IP="$(tfval php_app_ip "10.1.2.27")"
        PREV_PHP_DB_IP="$(tfval php_db_ip "10.1.2.28")"
        # 3-Tier hostnames (Linux)
        PREV_JAVA_FE_HOSTNAME="$(tfval java_fe_hostname "lin-java-fe")"
        PREV_JAVA_APP_HOSTNAME="$(tfval java_app_hostname "lin-java-app")"
        PREV_JAVA_DB_HOSTNAME="$(tfval java_db_hostname "lin-java-db")"
        PREV_DOTNET_FE_HOSTNAME="$(tfval dotnet_fe_hostname "lin-dotnet-fe")"
        PREV_DOTNET_APP_HOSTNAME="$(tfval dotnet_app_hostname "lin-dotnet-app")"
        PREV_DOTNET_DB_HOSTNAME="$(tfval dotnet_db_hostname "lin-dotnet-db")"
        PREV_PHP_FE_HOSTNAME="$(tfval php_fe_hostname "lin-php-fe")"
        PREV_PHP_APP_HOSTNAME="$(tfval php_app_hostname "lin-php-app")"
        PREV_PHP_DB_HOSTNAME="$(tfval php_db_hostname "lin-php-db")"
        # 3-Tier IPs & hostnames (Windows) — used when OS is Windows
        PREV_WIN_JAVA_FE_IP="$(tfval win_java_fe_ip "")"
        PREV_WIN_JAVA_APP_IP="$(tfval win_java_app_ip "")"
        PREV_WIN_JAVA_DB_IP="$(tfval win_java_db_ip "")"
        PREV_WIN_DOTNET_FE_IP="$(tfval win_dotnet_fe_ip "")"
        PREV_WIN_DOTNET_APP_IP="$(tfval win_dotnet_app_ip "")"
        PREV_WIN_DOTNET_DB_IP="$(tfval win_dotnet_db_ip "")"
        PREV_WIN_PHP_FE_IP="$(tfval win_php_fe_ip "")"
        PREV_WIN_PHP_APP_IP="$(tfval win_php_app_ip "")"
        PREV_WIN_PHP_DB_IP="$(tfval win_php_db_ip "")"
        PREV_WIN_JAVA_FE_HOSTNAME="$(tfval win_java_fe_hostname "")"
        PREV_WIN_JAVA_APP_HOSTNAME="$(tfval win_java_app_hostname "")"
        PREV_WIN_JAVA_DB_HOSTNAME="$(tfval win_java_db_hostname "")"
        PREV_WIN_DOTNET_FE_HOSTNAME="$(tfval win_dotnet_fe_hostname "")"
        PREV_WIN_DOTNET_APP_HOSTNAME="$(tfval win_dotnet_app_hostname "")"
        PREV_WIN_DOTNET_DB_HOSTNAME="$(tfval win_dotnet_db_hostname "")"
        PREV_WIN_PHP_FE_HOSTNAME="$(tfval win_php_fe_hostname "")"
        PREV_WIN_PHP_APP_HOSTNAME="$(tfval win_php_app_hostname "")"
        PREV_WIN_PHP_DB_HOSTNAME="$(tfval win_php_db_hostname "")"
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
    if $QUICK_MODE; then
        VSPHERE_SERVER="$PREV_VSPHERE_SERVER"
        VSPHERE_USER="$PREV_VSPHERE_USER"
        VSPHERE_SSL="$PREV_VSPHERE_SSL"
        step "Using saved: $VSPHERE_SERVER (user: $VSPHERE_USER)"
        prompt_secret "vCenter Password"; VSPHERE_PASSWORD="$REPLY"
        return
    fi
    prompt "vCenter Server FQDN or IP" "$PREV_VSPHERE_SERVER"; VSPHERE_SERVER="$REPLY"
    prompt "vCenter Username" "$PREV_VSPHERE_USER"; VSPHERE_USER="$REPLY"
    prompt_secret "vCenter Password"; VSPHERE_PASSWORD="$REPLY"
    prompt_yn "Allow unverified SSL?" "${PREV_VSPHERE_SSL:0:1}" && VSPHERE_SSL="true" || VSPHERE_SSL="false"
}

collect_infra() {
    header "Step 2/6 — vSphere Infrastructure"
    if $QUICK_MODE; then
        VSPHERE_DC="$PREV_VSPHERE_DC"; VSPHERE_CLUSTER="$PREV_VSPHERE_CLUSTER"
        VSPHERE_DS="$PREV_VSPHERE_DS"; VSPHERE_NET="$PREV_VSPHERE_NET"
        VSPHERE_FOLDER="$PREV_VSPHERE_FOLDER"
        VM_TEMPLATE="$PREV_VM_TEMPLATE"; WIN_TEMPLATE="$PREV_WIN_TEMPLATE"
        step "Using saved: DC=$VSPHERE_DC  Cluster=$VSPHERE_CLUSTER  DS=$VSPHERE_DS"
        return
    fi
    echo -e "  ${GR}Names must match your vCenter inventory exactly.${NC}"
    prompt "Datacenter name" "$PREV_VSPHERE_DC"; VSPHERE_DC="$REPLY"
    prompt "Compute Cluster name" "$PREV_VSPHERE_CLUSTER"; VSPHERE_CLUSTER="$REPLY"
    prompt "Datastore name" "$PREV_VSPHERE_DS"; VSPHERE_DS="$REPLY"
    prompt "Network / Port Group" "$PREV_VSPHERE_NET"; VSPHERE_NET="$REPLY"
    prompt_optional "VM Folder (blank for root)" "$PREV_VSPHERE_FOLDER"; VSPHERE_FOLDER="$REPLY"
    if [[ "$OS_CHOICE" == "linux" ]]; then
        prompt "Ubuntu 22.04 Template name" "$PREV_VM_TEMPLATE"; VM_TEMPLATE="$REPLY"
        WIN_TEMPLATE="$PREV_WIN_TEMPLATE"
    elif [[ "$OS_CHOICE" == "windows" ]]; then
        prompt "Windows Server 2019 Template name" "$PREV_WIN_TEMPLATE"; WIN_TEMPLATE="$REPLY"
        VM_TEMPLATE="$PREV_VM_TEMPLATE"
    else
        # Both
        prompt "Ubuntu 22.04 Template name" "$PREV_VM_TEMPLATE"; VM_TEMPLATE="$REPLY"
        prompt "Windows Server 2019 Template name" "$PREV_WIN_TEMPLATE"; WIN_TEMPLATE="$REPLY"
    fi
}

collect_network() {
    header "Step 3/6 — VM Network Settings"
    if $QUICK_MODE; then
        VM_GW="$PREV_VM_GW"; VM_MASK="$PREV_VM_MASK"
        VM_DOMAIN="$PREV_VM_DOMAIN"; VM_DNS="$PREV_VM_DNS"
        SSH_USER="$PREV_SSH_USER"; SSH_AUTH_METHOD="$PREV_SSH_AUTH_METHOD"
        SSH_KEY="$PREV_SSH_KEY"
        step "Using saved: GW=$VM_GW/$VM_MASK  DNS=$VM_DNS  SSH user=$SSH_USER"
        if [[ "$OS_CHOICE" == "linux" || "$OS_CHOICE" == "both" ]]; then
            if [[ "$SSH_AUTH_METHOD" == "key" ]]; then
                SSH_PASSWORD=""
            else
                prompt_secret "SSH password for user '$SSH_USER'"; SSH_PASSWORD="$REPLY"
            fi
        else
            SSH_PASSWORD=""
        fi
        if [[ "$OS_CHOICE" == "windows" || "$OS_CHOICE" == "both" ]]; then
            prompt_secret "Windows Administrator password"; WIN_ADMIN_PASS="$REPLY"
        else
            WIN_ADMIN_PASS=""
        fi
        return
    fi
    prompt_ip "Default Gateway IP" "$PREV_VM_GW"; VM_GW="$REPLY"
    prompt "Subnet mask (CIDR bits)" "$PREV_VM_MASK"; VM_MASK="$REPLY"
    prompt "Domain suffix" "$PREV_VM_DOMAIN"; VM_DOMAIN="$REPLY"
    prompt "DNS Servers (comma-sep)" "$PREV_VM_DNS"; VM_DNS="$REPLY"

    if [[ "$OS_CHOICE" == "linux" || "$OS_CHOICE" == "both" ]]; then
        prompt "SSH username in template" "$PREV_SSH_USER"; SSH_USER="$REPLY"

        echo ""
        echo -e "  ${Y}How will Ansible connect to the Linux VMs?${NC}"
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
    else
        SSH_USER="$PREV_SSH_USER"; SSH_AUTH_METHOD="password"; SSH_PASSWORD=""; SSH_KEY=""
    fi

    if [[ "$OS_CHOICE" == "windows" || "$OS_CHOICE" == "both" ]]; then
        prompt_secret "Windows Administrator password"; WIN_ADMIN_PASS="$REPLY"
    else
        WIN_ADMIN_PASS="${WIN_ADMIN_PASS:-}"
    fi
}

collect_vms() {
    header "Step 4/6 — VM Sizing, Hostnames & IP Addresses"
    echo -e "  ${GR}Static IPs on the same subnet as gateway $VM_GW${NC}\n"

    # Initialize all IPs to defaults (single-VM)
    JAVA_IP="${PREV_JAVA_IP:-10.1.2.7}"; JAVA_CPU="${PREV_JAVA_CPU:-2}"; JAVA_MEM="${PREV_JAVA_MEM:-4096}"; JAVA_DISK="${PREV_JAVA_DISK:-40}"
    DOTNET_IP="${PREV_DOTNET_IP:-10.1.2.8}"; DOTNET_CPU="${PREV_DOTNET_CPU:-2}"; DOTNET_MEM="${PREV_DOTNET_MEM:-4096}"; DOTNET_DISK="${PREV_DOTNET_DISK:-40}"
    PHP_IP="${PREV_PHP_IP:-10.1.2.9}"; PHP_CPU="${PREV_PHP_CPU:-2}"; PHP_MEM="${PREV_PHP_MEM:-2048}"; PHP_DISK="${PREV_PHP_DISK:-30}"
    # Initialize single-VM hostnames
    JAVA_HOSTNAME="${PREV_JAVA_HOSTNAME:-legacy-java-vm}"; DOTNET_HOSTNAME="${PREV_DOTNET_HOSTNAME:-legacy-dotnet-vm}"; PHP_HOSTNAME="${PREV_PHP_HOSTNAME:-legacy-php-vm}"
    # Initialize 3-tier IPs & sizing
    JAVA_FE_IP="${PREV_JAVA_FE_IP:-10.1.2.20}"; JAVA_APP_IP="${PREV_JAVA_APP_IP:-10.1.2.21}"; JAVA_DB_IP="${PREV_JAVA_DB_IP:-10.1.2.22}"
    DOTNET_FE_IP="${PREV_DOTNET_FE_IP:-10.1.2.23}"; DOTNET_APP_IP="${PREV_DOTNET_APP_IP:-10.1.2.24}"; DOTNET_DB_IP="${PREV_DOTNET_DB_IP:-10.1.2.25}"
    PHP_FE_IP="${PREV_PHP_FE_IP:-10.1.2.26}"; PHP_APP_IP="${PREV_PHP_APP_IP:-10.1.2.27}"; PHP_DB_IP="${PREV_PHP_DB_IP:-10.1.2.28}"
    FE_CPU="${PREV_FE_CPU:-1}"; FE_MEM="${PREV_FE_MEM:-2048}"; FE_DISK="${PREV_FE_DISK:-20}"
    APP_CPU="${PREV_APP_CPU:-2}"; APP_MEM="${PREV_APP_MEM:-4096}"; APP_DISK="${PREV_APP_DISK:-40}"
    DB_CPU="${PREV_DB_CPU:-2}"; DB_MEM="${PREV_DB_MEM:-4096}"; DB_DISK="${PREV_DB_DISK:-60}"
    # Initialize 3-tier hostnames
    # Discard stale Linux hostnames that lack the "lin-" prefix (or contain "win-")
    _lh() { local v="$1"; [[ "$v" != lin-* ]] && echo "" || echo "$v"; }
    JAVA_FE_HOSTNAME="$(_lh "$PREV_JAVA_FE_HOSTNAME")"; JAVA_FE_HOSTNAME="${JAVA_FE_HOSTNAME:-lin-java-fe}"
    JAVA_APP_HOSTNAME="$(_lh "$PREV_JAVA_APP_HOSTNAME")"; JAVA_APP_HOSTNAME="${JAVA_APP_HOSTNAME:-lin-java-app}"
    JAVA_DB_HOSTNAME="$(_lh "$PREV_JAVA_DB_HOSTNAME")"; JAVA_DB_HOSTNAME="${JAVA_DB_HOSTNAME:-lin-java-db}"
    DOTNET_FE_HOSTNAME="$(_lh "$PREV_DOTNET_FE_HOSTNAME")"; DOTNET_FE_HOSTNAME="${DOTNET_FE_HOSTNAME:-lin-dotnet-fe}"
    DOTNET_APP_HOSTNAME="$(_lh "$PREV_DOTNET_APP_HOSTNAME")"; DOTNET_APP_HOSTNAME="${DOTNET_APP_HOSTNAME:-lin-dotnet-app}"
    DOTNET_DB_HOSTNAME="$(_lh "$PREV_DOTNET_DB_HOSTNAME")"; DOTNET_DB_HOSTNAME="${DOTNET_DB_HOSTNAME:-lin-dotnet-db}"
    PHP_FE_HOSTNAME="$(_lh "$PREV_PHP_FE_HOSTNAME")"; PHP_FE_HOSTNAME="${PHP_FE_HOSTNAME:-lin-php-fe}"
    PHP_APP_HOSTNAME="$(_lh "$PREV_PHP_APP_HOSTNAME")"; PHP_APP_HOSTNAME="${PHP_APP_HOSTNAME:-lin-php-app}"
    PHP_DB_HOSTNAME="$(_lh "$PREV_PHP_DB_HOSTNAME")"; PHP_DB_HOSTNAME="${PHP_DB_HOSTNAME:-lin-php-db}"

    # Override with Windows 3-tier values when deploying Windows
    if [[ "$DEPLOY_MODE" == "windows-3tier" ]]; then
        # IPs: cascade from saved win_ → saved linux_ → default
        JAVA_FE_IP="${PREV_WIN_JAVA_FE_IP:-${PREV_JAVA_FE_IP:-10.1.2.20}}"; JAVA_APP_IP="${PREV_WIN_JAVA_APP_IP:-${PREV_JAVA_APP_IP:-10.1.2.21}}"; JAVA_DB_IP="${PREV_WIN_JAVA_DB_IP:-${PREV_JAVA_DB_IP:-10.1.2.22}}"
        DOTNET_FE_IP="${PREV_WIN_DOTNET_FE_IP:-${PREV_DOTNET_FE_IP:-10.1.2.23}}"; DOTNET_APP_IP="${PREV_WIN_DOTNET_APP_IP:-${PREV_DOTNET_APP_IP:-10.1.2.24}}"; DOTNET_DB_IP="${PREV_WIN_DOTNET_DB_IP:-${PREV_DOTNET_DB_IP:-10.1.2.25}}"
        PHP_FE_IP="${PREV_WIN_PHP_FE_IP:-${PREV_PHP_FE_IP:-10.1.2.26}}"; PHP_APP_IP="${PREV_WIN_PHP_APP_IP:-${PREV_PHP_APP_IP:-10.1.2.27}}"; PHP_DB_IP="${PREV_WIN_PHP_DB_IP:-${PREV_PHP_DB_IP:-10.1.2.28}}"
        # Hostnames: discard stale win_ values that match linux_ (from previous cascading bug)
        [[ "$PREV_WIN_JAVA_FE_HOSTNAME" == "$PREV_JAVA_FE_HOSTNAME" ]] && PREV_WIN_JAVA_FE_HOSTNAME=""
        [[ "$PREV_WIN_JAVA_APP_HOSTNAME" == "$PREV_JAVA_APP_HOSTNAME" ]] && PREV_WIN_JAVA_APP_HOSTNAME=""
        [[ "$PREV_WIN_JAVA_DB_HOSTNAME" == "$PREV_JAVA_DB_HOSTNAME" ]] && PREV_WIN_JAVA_DB_HOSTNAME=""
        [[ "$PREV_WIN_DOTNET_FE_HOSTNAME" == "$PREV_DOTNET_FE_HOSTNAME" ]] && PREV_WIN_DOTNET_FE_HOSTNAME=""
        [[ "$PREV_WIN_DOTNET_APP_HOSTNAME" == "$PREV_DOTNET_APP_HOSTNAME" ]] && PREV_WIN_DOTNET_APP_HOSTNAME=""
        [[ "$PREV_WIN_DOTNET_DB_HOSTNAME" == "$PREV_DOTNET_DB_HOSTNAME" ]] && PREV_WIN_DOTNET_DB_HOSTNAME=""
        [[ "$PREV_WIN_PHP_FE_HOSTNAME" == "$PREV_PHP_FE_HOSTNAME" ]] && PREV_WIN_PHP_FE_HOSTNAME=""
        [[ "$PREV_WIN_PHP_APP_HOSTNAME" == "$PREV_PHP_APP_HOSTNAME" ]] && PREV_WIN_PHP_APP_HOSTNAME=""
        [[ "$PREV_WIN_PHP_DB_HOSTNAME" == "$PREV_PHP_DB_HOSTNAME" ]] && PREV_WIN_PHP_DB_HOSTNAME=""
        JAVA_FE_HOSTNAME="${PREV_WIN_JAVA_FE_HOSTNAME:-win-java-fe}"; JAVA_APP_HOSTNAME="${PREV_WIN_JAVA_APP_HOSTNAME:-win-java-app}"; JAVA_DB_HOSTNAME="${PREV_WIN_JAVA_DB_HOSTNAME:-win-java-db}"
        DOTNET_FE_HOSTNAME="${PREV_WIN_DOTNET_FE_HOSTNAME:-win-dotnet-fe}"; DOTNET_APP_HOSTNAME="${PREV_WIN_DOTNET_APP_HOSTNAME:-win-dotnet-app}"; DOTNET_DB_HOSTNAME="${PREV_WIN_DOTNET_DB_HOSTNAME:-win-dotnet-db}"
        PHP_FE_HOSTNAME="${PREV_WIN_PHP_FE_HOSTNAME:-win-php-fe}"; PHP_APP_HOSTNAME="${PREV_WIN_PHP_APP_HOSTNAME:-win-php-app}"; PHP_DB_HOSTNAME="${PREV_WIN_PHP_DB_HOSTNAME:-win-php-db}"
    fi

    # Populate WIN_ variables from saved values for "both" mode (used by summary + write_tfvars)
    if [[ "$OS_CHOICE" == "both" ]]; then
        WIN_JAVA_FE_HOSTNAME="${PREV_WIN_JAVA_FE_HOSTNAME:-win-java-fe}"; WIN_JAVA_APP_HOSTNAME="${PREV_WIN_JAVA_APP_HOSTNAME:-win-java-app}"; WIN_JAVA_DB_HOSTNAME="${PREV_WIN_JAVA_DB_HOSTNAME:-win-java-db}"
        WIN_DOTNET_FE_HOSTNAME="${PREV_WIN_DOTNET_FE_HOSTNAME:-win-dotnet-fe}"; WIN_DOTNET_APP_HOSTNAME="${PREV_WIN_DOTNET_APP_HOSTNAME:-win-dotnet-app}"; WIN_DOTNET_DB_HOSTNAME="${PREV_WIN_DOTNET_DB_HOSTNAME:-win-dotnet-db}"
        WIN_PHP_FE_HOSTNAME="${PREV_WIN_PHP_FE_HOSTNAME:-win-php-fe}"; WIN_PHP_APP_HOSTNAME="${PREV_WIN_PHP_APP_HOSTNAME:-win-php-app}"; WIN_PHP_DB_HOSTNAME="${PREV_WIN_PHP_DB_HOSTNAME:-win-php-db}"
        WIN_JAVA_FE_IP="${PREV_WIN_JAVA_FE_IP:-10.1.3.30}"; WIN_JAVA_APP_IP="${PREV_WIN_JAVA_APP_IP:-10.1.3.31}"; WIN_JAVA_DB_IP="${PREV_WIN_JAVA_DB_IP:-10.1.3.32}"
        WIN_DOTNET_FE_IP="${PREV_WIN_DOTNET_FE_IP:-10.1.3.33}"; WIN_DOTNET_APP_IP="${PREV_WIN_DOTNET_APP_IP:-10.1.3.34}"; WIN_DOTNET_DB_IP="${PREV_WIN_DOTNET_DB_IP:-10.1.3.35}"
        WIN_PHP_FE_IP="${PREV_WIN_PHP_FE_IP:-10.1.3.36}"; WIN_PHP_APP_IP="${PREV_WIN_PHP_APP_IP:-10.1.3.37}"; WIN_PHP_DB_IP="${PREV_WIN_PHP_DB_IP:-10.1.3.38}"
    fi

    if $QUICK_MODE; then
        step "Using saved VM sizing, hostnames and IPs from previous run"
        return
    fi

    if [[ "$ARCH_CHOICE" == "3tier" ]]; then
        echo -e "  ${Y}--- 3-Tier Architecture ---${NC}"
        echo ""
        echo -e "  ${Y}How would you like to configure VM hardware?${NC}"
        echo -e "    ${G}1)${NC} Same config for all VMs     — one set of CPU/RAM/Disk applied to every VM"
        echo -e "    ${G}2)${NC} Custom config per tier       — separate CPU/RAM/Disk for Frontend, App, Database"
        echo -e "    ${G}3)${NC} Use recommended defaults    — Frontend: 1CPU/2GB/20GB, App: 2CPU/4GB/40GB, DB: 2CPU/4GB/60GB"
        local default_hw_choice="3"
        read -rp "  Choice [1/2/3] (default: $default_hw_choice): " HW_CHOICE
        HW_CHOICE="${HW_CHOICE:-$default_hw_choice}"

        if [[ "$HW_CHOICE" == "1" ]]; then
            echo ""
            echo -e "  ${Y}--- All VMs (Frontend + App Server + Database) ---${NC}"
            prompt "  CPUs" "${PREV_APP_CPU:-2}"; local ALL_CPU="$REPLY"
            prompt "  Memory MB" "${PREV_APP_MEM:-4096}"; local ALL_MEM="$REPLY"
            prompt "  Disk GB" "${PREV_APP_DISK:-40}"; local ALL_DISK="$REPLY"
            FE_CPU="$ALL_CPU"; FE_MEM="$ALL_MEM"; FE_DISK="$ALL_DISK"
            APP_CPU="$ALL_CPU"; APP_MEM="$ALL_MEM"; APP_DISK="$ALL_DISK"
            DB_CPU="$ALL_CPU"; DB_MEM="$ALL_MEM"; DB_DISK="$ALL_DISK"
        elif [[ "$HW_CHOICE" == "2" ]]; then
            echo ""
            echo -e "  ${Y}--- Frontend VMs (Nginx / IIS+ARR) ---${NC}"
            prompt "  Frontend CPUs" "${PREV_FE_CPU:-1}"; FE_CPU="$REPLY"
            prompt "  Frontend Memory MB" "${PREV_FE_MEM:-2048}"; FE_MEM="$REPLY"
            prompt "  Frontend Disk GB" "${PREV_FE_DISK:-20}"; FE_DISK="$REPLY"
            echo ""
            echo -e "  ${Y}--- App Server VMs (Spring Boot / ASP.NET / Laravel) ---${NC}"
            prompt "  App Server CPUs" "${PREV_APP_CPU:-2}"; APP_CPU="$REPLY"
            prompt "  App Server Memory MB" "${PREV_APP_MEM:-4096}"; APP_MEM="$REPLY"
            prompt "  App Server Disk GB" "${PREV_APP_DISK:-40}"; APP_DISK="$REPLY"
            echo ""
            echo -e "  ${Y}--- Database VMs (PostgreSQL / SQL Server / MySQL) ---${NC}"
            prompt "  Database CPUs" "${PREV_DB_CPU:-2}"; DB_CPU="$REPLY"
            prompt "  Database Memory MB" "${PREV_DB_MEM:-4096}"; DB_MEM="$REPLY"
            prompt "  Database Disk GB" "${PREV_DB_DISK:-60}"; DB_DISK="$REPLY"
        else
            FE_CPU=1; FE_MEM=2048; FE_DISK=20
            APP_CPU=2; APP_MEM=4096; APP_DISK=40
            DB_CPU=2; DB_MEM=4096; DB_DISK=60
            step "Using recommended defaults: FE=${FE_CPU}CPU/${FE_MEM}MB/${FE_DISK}GB, App=${APP_CPU}CPU/${APP_MEM}MB/${APP_DISK}GB, DB=${DB_CPU}CPU/${DB_MEM}MB/${DB_DISK}GB"
        fi

        echo ""
        echo -e "  ${Y}--- VM Hostnames & IP Addresses ---${NC}\n"

        if [[ "$OS_CHOICE" == "both" ]]; then
            # --- Prompt separately for Linux VMs ---
            # Use sanitized JAVA_FE_HOSTNAME etc. (set above, win- names stripped)
            echo -e "  ${C}=== Linux VMs ===${NC}\n"

            if [[ "$DEPLOY_JAVA" == "true" ]]; then
                echo -e "  ${Y}--- Java Stack (Linux) ---${NC}"
                prompt "  Java Frontend hostname" "$JAVA_FE_HOSTNAME"; JAVA_FE_HOSTNAME="$REPLY"
                prompt_ip "  Java Frontend IP" "${PREV_JAVA_FE_IP:-10.1.2.20}"; JAVA_FE_IP="$REPLY"
                prompt "  Java App Server hostname" "$JAVA_APP_HOSTNAME"; JAVA_APP_HOSTNAME="$REPLY"
                prompt_ip "  Java App Server IP" "${PREV_JAVA_APP_IP:-10.1.2.21}"; JAVA_APP_IP="$REPLY"
                prompt "  Java Database hostname" "$JAVA_DB_HOSTNAME"; JAVA_DB_HOSTNAME="$REPLY"
                prompt_ip "  Java Database IP" "${PREV_JAVA_DB_IP:-10.1.2.22}"; JAVA_DB_IP="$REPLY"
                echo ""
            fi

            if [[ "$DEPLOY_DOTNET" == "true" ]]; then
                echo -e "  ${Y}--- .NET Stack (Linux) ---${NC}"
                prompt "  .NET Frontend hostname" "$DOTNET_FE_HOSTNAME"; DOTNET_FE_HOSTNAME="$REPLY"
                prompt_ip "  .NET Frontend IP" "${PREV_DOTNET_FE_IP:-10.1.2.23}"; DOTNET_FE_IP="$REPLY"
                prompt "  .NET App Server hostname" "$DOTNET_APP_HOSTNAME"; DOTNET_APP_HOSTNAME="$REPLY"
                prompt_ip "  .NET App Server IP" "${PREV_DOTNET_APP_IP:-10.1.2.24}"; DOTNET_APP_IP="$REPLY"
                prompt "  .NET Database hostname" "$DOTNET_DB_HOSTNAME"; DOTNET_DB_HOSTNAME="$REPLY"
                prompt_ip "  .NET Database IP" "${PREV_DOTNET_DB_IP:-10.1.2.25}"; DOTNET_DB_IP="$REPLY"
                echo ""
            fi

            if [[ "$DEPLOY_PHP" == "true" ]]; then
                echo -e "  ${Y}--- PHP Stack (Linux) ---${NC}"
                prompt "  PHP Frontend hostname" "$PHP_FE_HOSTNAME"; PHP_FE_HOSTNAME="$REPLY"
                prompt_ip "  PHP Frontend IP" "${PREV_PHP_FE_IP:-10.1.2.26}"; PHP_FE_IP="$REPLY"
                prompt "  PHP App Server hostname" "$PHP_APP_HOSTNAME"; PHP_APP_HOSTNAME="$REPLY"
                prompt_ip "  PHP App Server IP" "${PREV_PHP_APP_IP:-10.1.2.27}"; PHP_APP_IP="$REPLY"
                prompt "  PHP Database hostname" "$PHP_DB_HOSTNAME"; PHP_DB_HOSTNAME="$REPLY"
                prompt_ip "  PHP Database IP" "${PREV_PHP_DB_IP:-10.1.2.28}"; PHP_DB_IP="$REPLY"
            fi

            echo ""
            echo -e "  ${C}=== Windows VMs ===${NC}\n"

            if [[ "$DEPLOY_JAVA" == "true" ]]; then
                echo -e "  ${Y}--- Java Stack (Windows) ---${NC}"
                prompt "  Java Frontend hostname" "${PREV_WIN_JAVA_FE_HOSTNAME:-win-java-fe}"; WIN_JAVA_FE_HOSTNAME="$REPLY"
                prompt_ip "  Java Frontend IP" "${PREV_WIN_JAVA_FE_IP:-10.1.2.30}"; WIN_JAVA_FE_IP="$REPLY"
                prompt "  Java App Server hostname" "${PREV_WIN_JAVA_APP_HOSTNAME:-win-java-app}"; WIN_JAVA_APP_HOSTNAME="$REPLY"
                prompt_ip "  Java App Server IP" "${PREV_WIN_JAVA_APP_IP:-10.1.2.31}"; WIN_JAVA_APP_IP="$REPLY"
                prompt "  Java Database hostname" "${PREV_WIN_JAVA_DB_HOSTNAME:-win-java-db}"; WIN_JAVA_DB_HOSTNAME="$REPLY"
                prompt_ip "  Java Database IP" "${PREV_WIN_JAVA_DB_IP:-10.1.2.32}"; WIN_JAVA_DB_IP="$REPLY"
                echo ""
            fi

            if [[ "$DEPLOY_DOTNET" == "true" ]]; then
                echo -e "  ${Y}--- .NET Stack (Windows) ---${NC}"
                prompt "  .NET Frontend hostname" "${PREV_WIN_DOTNET_FE_HOSTNAME:-win-dotnet-fe}"; WIN_DOTNET_FE_HOSTNAME="$REPLY"
                prompt_ip "  .NET Frontend IP" "${PREV_WIN_DOTNET_FE_IP:-10.1.2.33}"; WIN_DOTNET_FE_IP="$REPLY"
                prompt "  .NET App Server hostname" "${PREV_WIN_DOTNET_APP_HOSTNAME:-win-dotnet-app}"; WIN_DOTNET_APP_HOSTNAME="$REPLY"
                prompt_ip "  .NET App Server IP" "${PREV_WIN_DOTNET_APP_IP:-10.1.2.34}"; WIN_DOTNET_APP_IP="$REPLY"
                prompt "  .NET Database hostname" "${PREV_WIN_DOTNET_DB_HOSTNAME:-win-dotnet-db}"; WIN_DOTNET_DB_HOSTNAME="$REPLY"
                prompt_ip "  .NET Database IP" "${PREV_WIN_DOTNET_DB_IP:-10.1.2.35}"; WIN_DOTNET_DB_IP="$REPLY"
                echo ""
            fi

            if [[ "$DEPLOY_PHP" == "true" ]]; then
                echo -e "  ${Y}--- PHP Stack (Windows) ---${NC}"
                prompt "  PHP Frontend hostname" "${PREV_WIN_PHP_FE_HOSTNAME:-win-php-fe}"; WIN_PHP_FE_HOSTNAME="$REPLY"
                prompt_ip "  PHP Frontend IP" "${PREV_WIN_PHP_FE_IP:-10.1.2.36}"; WIN_PHP_FE_IP="$REPLY"
                prompt "  PHP App Server hostname" "${PREV_WIN_PHP_APP_HOSTNAME:-win-php-app}"; WIN_PHP_APP_HOSTNAME="$REPLY"
                prompt_ip "  PHP App Server IP" "${PREV_WIN_PHP_APP_IP:-10.1.2.37}"; WIN_PHP_APP_IP="$REPLY"
                prompt "  PHP Database hostname" "${PREV_WIN_PHP_DB_HOSTNAME:-win-php-db}"; WIN_PHP_DB_HOSTNAME="$REPLY"
                prompt_ip "  PHP Database IP" "${PREV_WIN_PHP_DB_IP:-10.1.2.38}"; WIN_PHP_DB_IP="$REPLY"
            fi

        else
            # --- Single OS mode: prompt once ---
            if [[ "$DEPLOY_JAVA" == "true" ]]; then
                echo -e "  ${Y}--- Java Stack ---${NC}"
                prompt "  Java Frontend hostname" "$JAVA_FE_HOSTNAME"; JAVA_FE_HOSTNAME="$REPLY"
                prompt_ip "  Java Frontend IP" "$JAVA_FE_IP"; JAVA_FE_IP="$REPLY"
                prompt "  Java App Server hostname" "$JAVA_APP_HOSTNAME"; JAVA_APP_HOSTNAME="$REPLY"
                prompt_ip "  Java App Server IP" "$JAVA_APP_IP"; JAVA_APP_IP="$REPLY"
                prompt "  Java Database hostname" "$JAVA_DB_HOSTNAME"; JAVA_DB_HOSTNAME="$REPLY"
                prompt_ip "  Java Database IP" "$JAVA_DB_IP"; JAVA_DB_IP="$REPLY"
                echo ""
            fi

            if [[ "$DEPLOY_DOTNET" == "true" ]]; then
                echo -e "  ${Y}--- .NET Stack ---${NC}"
                prompt "  .NET Frontend hostname" "$DOTNET_FE_HOSTNAME"; DOTNET_FE_HOSTNAME="$REPLY"
                prompt_ip "  .NET Frontend IP" "$DOTNET_FE_IP"; DOTNET_FE_IP="$REPLY"
                prompt "  .NET App Server hostname" "$DOTNET_APP_HOSTNAME"; DOTNET_APP_HOSTNAME="$REPLY"
                prompt_ip "  .NET App Server IP" "$DOTNET_APP_IP"; DOTNET_APP_IP="$REPLY"
                prompt "  .NET Database hostname" "$DOTNET_DB_HOSTNAME"; DOTNET_DB_HOSTNAME="$REPLY"
                prompt_ip "  .NET Database IP" "$DOTNET_DB_IP"; DOTNET_DB_IP="$REPLY"
                echo ""
            fi

            if [[ "$DEPLOY_PHP" == "true" ]]; then
                echo -e "  ${Y}--- PHP Stack ---${NC}"
                prompt "  PHP Frontend hostname" "$PHP_FE_HOSTNAME"; PHP_FE_HOSTNAME="$REPLY"
                prompt_ip "  PHP Frontend IP" "$PHP_FE_IP"; PHP_FE_IP="$REPLY"
                prompt "  PHP App Server hostname" "$PHP_APP_HOSTNAME"; PHP_APP_HOSTNAME="$REPLY"
                prompt_ip "  PHP App Server IP" "$PHP_APP_IP"; PHP_APP_IP="$REPLY"
                prompt "  PHP Database hostname" "$PHP_DB_HOSTNAME"; PHP_DB_HOSTNAME="$REPLY"
                prompt_ip "  PHP Database IP" "$PHP_DB_IP"; PHP_DB_IP="$REPLY"
            fi
        fi

    else
        # Single-VM mode: prompt only for selected apps
        if [[ "$DEPLOY_JAVA" == "true" ]]; then
            local jlabel="Java VM (PetClinic + PostgreSQL)"
            [[ "$OS_CHOICE" != "linux" ]] && jlabel="Java VM (PetClinic + PostgreSQL) — Windows"
            echo -e "  ${Y}--- $jlabel ---${NC}"
            prompt "  Hostname" "$PREV_JAVA_HOSTNAME"; JAVA_HOSTNAME="$REPLY"
            prompt_ip "  IP" "$PREV_JAVA_IP"; JAVA_IP="$REPLY"
            prompt "  CPUs" "$PREV_JAVA_CPU"; JAVA_CPU="$REPLY"
            prompt "  Memory MB" "$PREV_JAVA_MEM"; JAVA_MEM="$REPLY"
            prompt "  Disk GB" "$PREV_JAVA_DISK"; JAVA_DISK="$REPLY"
            echo ""
        fi

        if [[ "$DEPLOY_DOTNET" == "true" ]]; then
            local dlabel=".NET VM (ASP.NET + SQL Server)"
            [[ "$OS_CHOICE" != "linux" ]] && dlabel=".NET VM (IIS + ASP.NET + SQL Server) — Windows"
            echo -e "  ${Y}--- $dlabel ---${NC}"
            prompt "  Hostname" "$PREV_DOTNET_HOSTNAME"; DOTNET_HOSTNAME="$REPLY"
            prompt_ip "  IP" "$PREV_DOTNET_IP"; DOTNET_IP="$REPLY"
            prompt "  CPUs" "$PREV_DOTNET_CPU"; DOTNET_CPU="$REPLY"
            prompt "  Memory MB" "$PREV_DOTNET_MEM"; DOTNET_MEM="$REPLY"
            prompt "  Disk GB" "$PREV_DOTNET_DISK"; DOTNET_DISK="$REPLY"
            echo ""
        fi

        if [[ "$DEPLOY_PHP" == "true" ]]; then
            local plabel="PHP VM (Laravel + MySQL)"
            [[ "$OS_CHOICE" != "linux" ]] && plabel="PHP VM (IIS + Laravel + MySQL) — Windows"
            echo -e "  ${Y}--- $plabel ---${NC}"
            prompt "  Hostname" "$PREV_PHP_HOSTNAME"; PHP_HOSTNAME="$REPLY"
            prompt_ip "  IP" "$PREV_PHP_IP"; PHP_IP="$REPLY"
            prompt "  CPUs" "$PREV_PHP_CPU"; PHP_CPU="$REPLY"
            prompt "  Memory MB" "$PREV_PHP_MEM"; PHP_MEM="$REPLY"
            prompt "  Disk GB" "$PREV_PHP_DISK"; PHP_DISK="$REPLY"
        fi
    fi
}

collect_apps() {
    header "Step 5/6 — Application & Database Configuration"

    # Initialize all defaults (for unused apps in tfvars)
    PETCLINIC_REPO="$PREV_PETCLINIC_REPO"; PETCLINIC_BRANCH="$PREV_PETCLINIC_BRANCH"; JAVA_VER="$PREV_JAVA_VER"
    PG_PASS="placeholder"
    DOTNET_SDK="$PREV_DOTNET_SDK"; DOTNET_REPO="$PREV_DOTNET_REPO"; DOTNET_BRANCH="$PREV_DOTNET_BRANCH"
    MSSQL_PASS="Placeholder1!"
    PHP_VER="$PREV_PHP_VER"; PHP_REPO="$PREV_PHP_REPO"; PHP_BRANCH="$PREV_PHP_BRANCH"
    MYSQL_ROOT="placeholder"; MYSQL_APP="placeholder"

    if $QUICK_MODE; then
        step "Using saved app config from previous run"
        echo -e "  ${GR}Only prompting for database passwords (not saved)${NC}"
        [[ "$DEPLOY_JAVA" == "true" ]]   && { prompt_secret "  PostgreSQL password"; PG_PASS="$REPLY"; }
        [[ "$DEPLOY_DOTNET" == "true" ]] && { prompt_secret "  SQL Server SA password (8+ chars, complexity)"; MSSQL_PASS="$REPLY"; }
        if [[ "$DEPLOY_PHP" == "true" ]]; then
            prompt_secret "  MySQL root password"; MYSQL_ROOT="$REPLY"
            prompt_secret "  MySQL app user password"; MYSQL_APP="$REPLY"
        fi
        return
    fi

    if [[ "$DEPLOY_JAVA" == "true" ]]; then
        echo -e "  ${Y}--- Java / PetClinic ---${NC}"
        prompt "  Git repo" "$PREV_PETCLINIC_REPO"; PETCLINIC_REPO="$REPLY"
        prompt "  Branch" "$PREV_PETCLINIC_BRANCH"; PETCLINIC_BRANCH="$REPLY"
        prompt "  JDK version" "$PREV_JAVA_VER"; JAVA_VER="$REPLY"
        prompt_secret "  PostgreSQL password"; PG_PASS="$REPLY"
        echo ""
    fi

    if [[ "$DEPLOY_DOTNET" == "true" ]]; then
        echo -e "  ${Y}--- .NET / ASP.NET ---${NC}"
        if [[ "$OS_CHOICE" == "linux" ]]; then
            prompt "  .NET SDK version" "$PREV_DOTNET_SDK"; DOTNET_SDK="$REPLY"
            prompt "  Git repo" "$PREV_DOTNET_REPO"; DOTNET_REPO="$REPLY"
            prompt "  Branch" "$PREV_DOTNET_BRANCH"; DOTNET_BRANCH="$REPLY"
        fi
        prompt_secret "  SQL Server SA password (8+ chars, complexity)"; MSSQL_PASS="$REPLY"
        echo ""
    fi

    if [[ "$DEPLOY_PHP" == "true" ]]; then
        echo -e "  ${Y}--- PHP / Laravel ---${NC}"
        prompt "  PHP version" "$PREV_PHP_VER"; PHP_VER="$REPLY"
        prompt "  Git repo" "$PREV_PHP_REPO"; PHP_REPO="$REPLY"
        prompt "  Branch" "$PREV_PHP_BRANCH"; PHP_BRANCH="$REPLY"
        prompt_secret "  MySQL root password"; MYSQL_ROOT="$REPLY"
        prompt_secret "  MySQL app user password"; MYSQL_APP="$REPLY"
    fi
}

collect_migrate() {
    header "Step 6/6 — Azure Migrate Options"
    if $QUICK_MODE; then
        AZ_AGENT="$PREV_AZ_AGENT"
        step "Using saved: Azure Migrate Agent = $AZ_AGENT"
        return
    fi
    local default_yn; [[ "$PREV_AZ_AGENT" == "true" ]] && default_yn="y" || default_yn="n"
    prompt_yn "Install Azure Migrate Dependency Agent on VMs?" "$default_yn" && AZ_AGENT="true" || AZ_AGENT="false"
}

# ---------------------------------------------------------------------------
show_summary() {
    header "Configuration Summary"
    echo -e "  App Selection:  ${Y}${APP_SELECTION^^}${NC}"
    echo -e "  OS:             ${Y}${OS_CHOICE^^}${NC}"
    echo -e "  Architecture:   ${Y}${ARCH_CHOICE^^}${NC}"
    echo -e "  vCenter:        $VSPHERE_SERVER"
    echo -e "  Datacenter:     $VSPHERE_DC   Cluster: $VSPHERE_CLUSTER"
    if [[ "$OS_CHOICE" == "linux" ]]; then
        echo -e "  Template:       $VM_TEMPLATE (Linux)"
    elif [[ "$OS_CHOICE" == "windows" ]]; then
        echo -e "  Template:       $WIN_TEMPLATE (Windows)"
    else
        echo -e "  Templates:      $VM_TEMPLATE (Linux) / $WIN_TEMPLATE (Windows)"
    fi
    echo -e "  Network:        $VSPHERE_NET  Gateway: $VM_GW/$VM_MASK\n"

    for mode in "${DEPLOY_MODES[@]}"; do
        local os_label="Linux"
        [[ "$mode" == windows* ]] && os_label="Windows"
        echo -e "  ${C}--- $os_label Deployment ---${NC}"

        if [[ "$ARCH_CHOICE" == "3tier" ]]; then
            # When "both" mode, use WIN_ vars for Windows display
            local d_java_fe_h="$JAVA_FE_HOSTNAME" d_java_fe_ip="$JAVA_FE_IP"
            local d_java_app_h="$JAVA_APP_HOSTNAME" d_java_app_ip="$JAVA_APP_IP"
            local d_java_db_h="$JAVA_DB_HOSTNAME" d_java_db_ip="$JAVA_DB_IP"
            local d_dotnet_fe_h="$DOTNET_FE_HOSTNAME" d_dotnet_fe_ip="$DOTNET_FE_IP"
            local d_dotnet_app_h="$DOTNET_APP_HOSTNAME" d_dotnet_app_ip="$DOTNET_APP_IP"
            local d_dotnet_db_h="$DOTNET_DB_HOSTNAME" d_dotnet_db_ip="$DOTNET_DB_IP"
            local d_php_fe_h="$PHP_FE_HOSTNAME" d_php_fe_ip="$PHP_FE_IP"
            local d_php_app_h="$PHP_APP_HOSTNAME" d_php_app_ip="$PHP_APP_IP"
            local d_php_db_h="$PHP_DB_HOSTNAME" d_php_db_ip="$PHP_DB_IP"
            if [[ "$mode" == windows* && "$OS_CHOICE" == "both" ]]; then
                d_java_fe_h="${WIN_JAVA_FE_HOSTNAME:-$JAVA_FE_HOSTNAME}"; d_java_fe_ip="${WIN_JAVA_FE_IP:-$JAVA_FE_IP}"
                d_java_app_h="${WIN_JAVA_APP_HOSTNAME:-$JAVA_APP_HOSTNAME}"; d_java_app_ip="${WIN_JAVA_APP_IP:-$JAVA_APP_IP}"
                d_java_db_h="${WIN_JAVA_DB_HOSTNAME:-$JAVA_DB_HOSTNAME}"; d_java_db_ip="${WIN_JAVA_DB_IP:-$JAVA_DB_IP}"
                d_dotnet_fe_h="${WIN_DOTNET_FE_HOSTNAME:-$DOTNET_FE_HOSTNAME}"; d_dotnet_fe_ip="${WIN_DOTNET_FE_IP:-$DOTNET_FE_IP}"
                d_dotnet_app_h="${WIN_DOTNET_APP_HOSTNAME:-$DOTNET_APP_HOSTNAME}"; d_dotnet_app_ip="${WIN_DOTNET_APP_IP:-$DOTNET_APP_IP}"
                d_dotnet_db_h="${WIN_DOTNET_DB_HOSTNAME:-$DOTNET_DB_HOSTNAME}"; d_dotnet_db_ip="${WIN_DOTNET_DB_IP:-$DOTNET_DB_IP}"
                d_php_fe_h="${WIN_PHP_FE_HOSTNAME:-$PHP_FE_HOSTNAME}"; d_php_fe_ip="${WIN_PHP_FE_IP:-$PHP_FE_IP}"
                d_php_app_h="${WIN_PHP_APP_HOSTNAME:-$PHP_APP_HOSTNAME}"; d_php_app_ip="${WIN_PHP_APP_IP:-$PHP_APP_IP}"
                d_php_db_h="${WIN_PHP_DB_HOSTNAME:-$PHP_DB_HOSTNAME}"; d_php_db_ip="${WIN_PHP_DB_IP:-$PHP_DB_IP}"
            fi
            if [[ "$DEPLOY_JAVA" == "true" ]]; then
                echo -e "    ${Y}Java Stack:${NC}"
                echo -e "      Frontend    $d_java_fe_h  $d_java_fe_ip   ${FE_CPU}CPU / ${FE_MEM}MB / ${FE_DISK}GB"
                echo -e "      App Server  $d_java_app_h  $d_java_app_ip  ${APP_CPU}CPU / ${APP_MEM}MB / ${APP_DISK}GB"
                echo -e "      Database    $d_java_db_h  $d_java_db_ip   ${DB_CPU}CPU / ${DB_MEM}MB / ${DB_DISK}GB"
            fi
            if [[ "$DEPLOY_DOTNET" == "true" ]]; then
                echo -e "    ${Y}.NET Stack:${NC}"
                echo -e "      Frontend    $d_dotnet_fe_h  $d_dotnet_fe_ip   ${FE_CPU}CPU / ${FE_MEM}MB / ${FE_DISK}GB"
                echo -e "      App Server  $d_dotnet_app_h  $d_dotnet_app_ip  ${APP_CPU}CPU / ${APP_MEM}MB / ${APP_DISK}GB"
                echo -e "      Database    $d_dotnet_db_h  $d_dotnet_db_ip   ${DB_CPU}CPU / ${DB_MEM}MB / ${DB_DISK}GB"
            fi
            if [[ "$DEPLOY_PHP" == "true" ]]; then
                echo -e "    ${Y}PHP Stack:${NC}"
                echo -e "      Frontend    $d_php_fe_h  $d_php_fe_ip   ${FE_CPU}CPU / ${FE_MEM}MB / ${FE_DISK}GB"
                echo -e "      App Server  $d_php_app_h  $d_php_app_ip  ${APP_CPU}CPU / ${APP_MEM}MB / ${APP_DISK}GB"
                echo -e "      Database    $d_php_db_h  $d_php_db_ip   ${DB_CPU}CPU / ${DB_MEM}MB / ${DB_DISK}GB"
            fi
        else
            if [[ "$DEPLOY_JAVA" == "true" ]]; then
                echo -e "    Java  $JAVA_HOSTNAME  $JAVA_IP   ${JAVA_CPU}CPU / ${JAVA_MEM}MB / ${JAVA_DISK}GB"
            fi
            if [[ "$DEPLOY_DOTNET" == "true" ]]; then
                echo -e "    .NET  $DOTNET_HOSTNAME  $DOTNET_IP ${DOTNET_CPU}CPU / ${DOTNET_MEM}MB / ${DOTNET_DISK}GB"
            fi
            if [[ "$DEPLOY_PHP" == "true" ]]; then
                echo -e "    PHP   $PHP_HOSTNAME  $PHP_IP    ${PHP_CPU}CPU / ${PHP_MEM}MB / ${PHP_DISK}GB"
            fi
        fi
        echo ""
    done
}

# ---------------------------------------------------------------------------
write_tfvars() {
    step "Generating terraform/terraform.tfvars for mode: $DEPLOY_MODE ..."
    local dns_arr
    dns_arr=$(echo "$VM_DNS" | tr ',' '\n' | sed 's/^ *//;s/ *$//' | awk '{printf "\"%s\", ", $0}' | sed 's/, $//')

    # When deploying Windows 3-tier in single-OS mode, the wizard stores
    # user input in JAVA_FE_* etc. Copy them to WIN_ equivalents so the
    # heredoc writes correct values. Skip when "both" — already separate.
    if [[ "$DEPLOY_MODE" == "windows-3tier" && "$OS_CHOICE" != "both" ]]; then
        WIN_JAVA_FE_IP="$JAVA_FE_IP"; WIN_JAVA_APP_IP="$JAVA_APP_IP"; WIN_JAVA_DB_IP="$JAVA_DB_IP"
        WIN_JAVA_FE_HOSTNAME="$JAVA_FE_HOSTNAME"; WIN_JAVA_APP_HOSTNAME="$JAVA_APP_HOSTNAME"; WIN_JAVA_DB_HOSTNAME="$JAVA_DB_HOSTNAME"
        WIN_DOTNET_FE_IP="$DOTNET_FE_IP"; WIN_DOTNET_APP_IP="$DOTNET_APP_IP"; WIN_DOTNET_DB_IP="$DOTNET_DB_IP"
        WIN_DOTNET_FE_HOSTNAME="$DOTNET_FE_HOSTNAME"; WIN_DOTNET_APP_HOSTNAME="$DOTNET_APP_HOSTNAME"; WIN_DOTNET_DB_HOSTNAME="$DOTNET_DB_HOSTNAME"
        WIN_PHP_FE_IP="$PHP_FE_IP"; WIN_PHP_APP_IP="$PHP_APP_IP"; WIN_PHP_DB_IP="$PHP_DB_IP"
        WIN_PHP_FE_HOSTNAME="$PHP_FE_HOSTNAME"; WIN_PHP_APP_HOSTNAME="$PHP_APP_HOSTNAME"; WIN_PHP_DB_HOSTNAME="$PHP_DB_HOSTNAME"
    fi

    cat > "$TF_DIR/terraform.tfvars" <<EOF
# Auto-generated by setup-interactive.sh on $(date '+%Y-%m-%d %H:%M:%S')
# wizard_choices: app=$APP_SELECTION os=$OS_CHOICE arch=$ARCH_CHOICE

deploy_mode = "$DEPLOY_MODE"

deploy_java   = $DEPLOY_JAVA
deploy_dotnet = $DEPLOY_DOTNET
deploy_php    = $DEPLOY_PHP

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

java_vm_ip       = "$JAVA_IP"
java_vm_hostname = "$JAVA_HOSTNAME"
java_vm_cpus     = $JAVA_CPU
java_vm_memory   = $JAVA_MEM
java_vm_disk     = $JAVA_DISK

dotnet_vm_ip       = "$DOTNET_IP"
dotnet_vm_hostname = "$DOTNET_HOSTNAME"
dotnet_vm_cpus     = $DOTNET_CPU
dotnet_vm_memory   = $DOTNET_MEM
dotnet_vm_disk     = $DOTNET_DISK

php_vm_ip       = "$PHP_IP"
php_vm_hostname = "$PHP_HOSTNAME"
php_vm_cpus     = $PHP_CPU
php_vm_memory   = $PHP_MEM
php_vm_disk     = $PHP_DISK

win_template_name  = "$WIN_TEMPLATE"
win_admin_password = "$WIN_ADMIN_PASS"

# --- 3-Tier IPs & Hostnames (Linux) ---
java_fe_ip       = "${JAVA_FE_IP:-10.1.2.20}"
java_fe_hostname = "${JAVA_FE_HOSTNAME:-lin-java-fe}"
java_app_ip       = "${JAVA_APP_IP:-10.1.2.21}"
java_app_hostname = "${JAVA_APP_HOSTNAME:-lin-java-app}"
java_db_ip       = "${JAVA_DB_IP:-10.1.2.22}"
java_db_hostname = "${JAVA_DB_HOSTNAME:-lin-java-db}"
dotnet_fe_ip       = "${DOTNET_FE_IP:-10.1.2.23}"
dotnet_fe_hostname = "${DOTNET_FE_HOSTNAME:-lin-dotnet-fe}"
dotnet_app_ip       = "${DOTNET_APP_IP:-10.1.2.24}"
dotnet_app_hostname = "${DOTNET_APP_HOSTNAME:-lin-dotnet-app}"
dotnet_db_ip       = "${DOTNET_DB_IP:-10.1.2.25}"
dotnet_db_hostname = "${DOTNET_DB_HOSTNAME:-lin-dotnet-db}"
php_fe_ip       = "${PHP_FE_IP:-10.1.2.26}"
php_fe_hostname = "${PHP_FE_HOSTNAME:-lin-php-fe}"
php_app_ip       = "${PHP_APP_IP:-10.1.2.27}"
php_app_hostname = "${PHP_APP_HOSTNAME:-lin-php-app}"
php_db_ip       = "${PHP_DB_IP:-10.1.2.28}"
php_db_hostname = "${PHP_DB_HOSTNAME:-lin-php-db}"

# --- 3-Tier IPs & Hostnames (Windows) ---
win_java_fe_ip       = "${WIN_JAVA_FE_IP:-10.1.2.30}"
win_java_fe_hostname = "${WIN_JAVA_FE_HOSTNAME:-win-java-fe}"
win_java_app_ip       = "${WIN_JAVA_APP_IP:-10.1.2.31}"
win_java_app_hostname = "${WIN_JAVA_APP_HOSTNAME:-win-java-app}"
win_java_db_ip       = "${WIN_JAVA_DB_IP:-10.1.2.32}"
win_java_db_hostname = "${WIN_JAVA_DB_HOSTNAME:-win-java-db}"
win_dotnet_fe_ip       = "${WIN_DOTNET_FE_IP:-10.1.2.33}"
win_dotnet_fe_hostname = "${WIN_DOTNET_FE_HOSTNAME:-win-dotnet-fe}"
win_dotnet_app_ip       = "${WIN_DOTNET_APP_IP:-10.1.2.34}"
win_dotnet_app_hostname = "${WIN_DOTNET_APP_HOSTNAME:-win-dotnet-app}"
win_dotnet_db_ip       = "${WIN_DOTNET_DB_IP:-10.1.2.35}"
win_dotnet_db_hostname = "${WIN_DOTNET_DB_HOSTNAME:-win-dotnet-db}"
win_php_fe_ip       = "${WIN_PHP_FE_IP:-10.1.2.36}"
win_php_fe_hostname = "${WIN_PHP_FE_HOSTNAME:-win-php-fe}"
win_php_app_ip       = "${WIN_PHP_APP_IP:-10.1.2.37}"
win_php_app_hostname = "${WIN_PHP_APP_HOSTNAME:-win-php-app}"
win_php_db_ip       = "${WIN_PHP_DB_IP:-10.1.2.38}"
win_php_db_hostname = "${WIN_PHP_DB_HOSTNAME:-win-php-db}"

# --- 3-Tier VM Sizing ---
fe_cpus   = ${FE_CPU:-1}
fe_memory = ${FE_MEM:-2048}
fe_disk   = ${FE_DISK:-20}
app_cpus   = ${APP_CPU:-2}
app_memory = ${APP_MEM:-4096}
app_disk   = ${APP_DISK:-40}
db_cpus   = ${DB_CPU:-2}
db_memory = ${DB_MEM:-4096}
db_disk   = ${DB_DISK:-60}
EOF
    step "Created: terraform/terraform.tfvars"
}

write_ansible_vars() {
    step "Generating ansible/group_vars/all.yml ..."
    mkdir -p "$ANSIBLE_DIR/group_vars"

    cat > "$ANSIBLE_DIR/group_vars/all.yml" <<EOF
# Auto-generated by setup-interactive.sh on $(date '+%Y-%m-%d %H:%M:%S')

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

# DNS Registration (used by dns-register-*.yml playbooks)
dns_server: "${VM_DNS%%,*}"
dns_zone: "$VM_DOMAIN"
EOF
    step "Created: ansible/group_vars/all.yml"
}

write_inventory() {
    step "Generating ansible/inventory/hosts.ini for mode: $DEPLOY_MODE ..."
    mkdir -p "$ANSIBLE_DIR/inventory"
    local inv_file="$ANSIBLE_DIR/inventory/hosts.ini"

    # Only truncate on first call; subsequent calls (e.g. both linux + windows) append
    if [[ "${INVENTORY_INITIALIZED:-}" != "true" ]]; then
        echo "# Auto-generated by setup-interactive.sh on $(date '+%Y-%m-%d %H:%M:%S')" > "$inv_file"
        INVENTORY_INITIALIZED=true
    fi

    if [[ "$DEPLOY_MODE" == "linux" ]]; then
        if [[ "$SSH_AUTH_METHOD" == "password" ]]; then
            AUTH_LINE="ansible_ssh_pass=$SSH_PASSWORD ansible_become_pass=$SSH_PASSWORD ansible_ssh_common_args='-o StrictHostKeyChecking=no'"
        else
            AUTH_LINE="ansible_ssh_private_key_file=$SSH_KEY"
        fi
        [[ "$DEPLOY_JAVA" == "true" ]] && cat >> "$inv_file" <<EOF

[java_servers]
$JAVA_IP ansible_user=$SSH_USER $AUTH_LINE
EOF
        [[ "$DEPLOY_DOTNET" == "true" ]] && cat >> "$inv_file" <<EOF

[dotnet_servers]
$DOTNET_IP ansible_user=$SSH_USER $AUTH_LINE
EOF
        [[ "$DEPLOY_PHP" == "true" ]] && cat >> "$inv_file" <<EOF

[php_servers]
$PHP_IP ansible_user=$SSH_USER $AUTH_LINE
EOF
        {
            echo ""
            echo "[legacy_apps:children]"
            [[ "$DEPLOY_JAVA" == "true" ]] && echo "java_servers"
            [[ "$DEPLOY_DOTNET" == "true" ]] && echo "dotnet_servers"
            [[ "$DEPLOY_PHP" == "true" ]] && echo "php_servers"
        } >> "$inv_file"

    elif [[ "$DEPLOY_MODE" == "windows" ]]; then
        [[ "$DEPLOY_JAVA" == "true" ]] && cat >> "$inv_file" <<EOF

[win_java_servers]
$JAVA_IP
EOF
        [[ "$DEPLOY_DOTNET" == "true" ]] && cat >> "$inv_file" <<EOF

[win_dotnet_servers]
$DOTNET_IP
EOF
        [[ "$DEPLOY_PHP" == "true" ]] && cat >> "$inv_file" <<EOF

[win_php_servers]
$PHP_IP
EOF
        {
            echo ""
            echo "[win_servers:children]"
            [[ "$DEPLOY_JAVA" == "true" ]] && echo "win_java_servers"
            [[ "$DEPLOY_DOTNET" == "true" ]] && echo "win_dotnet_servers"
            [[ "$DEPLOY_PHP" == "true" ]] && echo "win_php_servers"
            echo ""
            echo "[win_servers:vars]"
            echo "ansible_connection=winrm"
            echo "ansible_winrm_transport=ntlm"
            echo "ansible_winrm_scheme=http"
            echo "ansible_user=Administrator"
            echo "ansible_password=$WIN_ADMIN_PASS"
            echo "ansible_port=5985"
            echo "ansible_become=false"
        } >> "$inv_file"

    elif [[ "$DEPLOY_MODE" == "linux-3tier" ]]; then
        if [[ "$SSH_AUTH_METHOD" == "password" ]]; then
            AUTH_LINE="ansible_ssh_pass=$SSH_PASSWORD ansible_become_pass=$SSH_PASSWORD ansible_ssh_common_args='-o StrictHostKeyChecking=no'"
        else
            AUTH_LINE="ansible_ssh_private_key_file=$SSH_KEY"
        fi


        [[ "$DEPLOY_JAVA" == "true" ]] && cat >> "$inv_file" <<EOF

[java_frontend]
$JAVA_FE_IP ansible_user=$SSH_USER $AUTH_LINE

[java_appserver]
$JAVA_APP_IP ansible_user=$SSH_USER $AUTH_LINE

[java_database]
$JAVA_DB_IP ansible_user=$SSH_USER $AUTH_LINE
EOF
        [[ "$DEPLOY_DOTNET" == "true" ]] && cat >> "$inv_file" <<EOF

[dotnet_frontend]
$DOTNET_FE_IP ansible_user=$SSH_USER $AUTH_LINE

[dotnet_appserver]
$DOTNET_APP_IP ansible_user=$SSH_USER $AUTH_LINE

[dotnet_database]
$DOTNET_DB_IP ansible_user=$SSH_USER $AUTH_LINE
EOF
        [[ "$DEPLOY_PHP" == "true" ]] && cat >> "$inv_file" <<EOF

[php_frontend]
$PHP_FE_IP ansible_user=$SSH_USER $AUTH_LINE

[php_appserver]
$PHP_APP_IP ansible_user=$SSH_USER $AUTH_LINE

[php_database]
$PHP_DB_IP ansible_user=$SSH_USER $AUTH_LINE
EOF
        {
            echo ""
            echo "[frontends:children]"
            [[ "$DEPLOY_JAVA" == "true" ]] && echo "java_frontend"
            [[ "$DEPLOY_DOTNET" == "true" ]] && echo "dotnet_frontend"
            [[ "$DEPLOY_PHP" == "true" ]] && echo "php_frontend"
            echo ""
            echo "[appservers:children]"
            [[ "$DEPLOY_JAVA" == "true" ]] && echo "java_appserver"
            [[ "$DEPLOY_DOTNET" == "true" ]] && echo "dotnet_appserver"
            [[ "$DEPLOY_PHP" == "true" ]] && echo "php_appserver"
            echo ""
            echo "[databases:children]"
            [[ "$DEPLOY_JAVA" == "true" ]] && echo "java_database"
            [[ "$DEPLOY_DOTNET" == "true" ]] && echo "dotnet_database"
            [[ "$DEPLOY_PHP" == "true" ]] && echo "php_database"
            echo ""
            echo "[legacy_apps_3tier:children]"
            echo "frontends"
            echo "appservers"
            echo "databases"
        } >> "$inv_file"

    elif [[ "$DEPLOY_MODE" == "windows-3tier" ]]; then

        # When "both" mode, use WIN_ vars; otherwise use base vars (same as user entered)
        local w_java_fe_ip="${JAVA_FE_IP:-}" w_java_app_ip="${JAVA_APP_IP:-}" w_java_db_ip="${JAVA_DB_IP:-}"
        local w_dotnet_fe_ip="${DOTNET_FE_IP:-}" w_dotnet_app_ip="${DOTNET_APP_IP:-}" w_dotnet_db_ip="${DOTNET_DB_IP:-}"
        local w_php_fe_ip="${PHP_FE_IP:-}" w_php_app_ip="${PHP_APP_IP:-}" w_php_db_ip="${PHP_DB_IP:-}"
        if [[ "${OS_CHOICE:-}" == "both" ]]; then
            w_java_fe_ip="${WIN_JAVA_FE_IP:-${JAVA_FE_IP:-}}"; w_java_app_ip="${WIN_JAVA_APP_IP:-${JAVA_APP_IP:-}}"; w_java_db_ip="${WIN_JAVA_DB_IP:-${JAVA_DB_IP:-}}"
            w_dotnet_fe_ip="${WIN_DOTNET_FE_IP:-${DOTNET_FE_IP:-}}"; w_dotnet_app_ip="${WIN_DOTNET_APP_IP:-${DOTNET_APP_IP:-}}"; w_dotnet_db_ip="${WIN_DOTNET_DB_IP:-${DOTNET_DB_IP:-}}"
            w_php_fe_ip="${WIN_PHP_FE_IP:-${PHP_FE_IP:-}}"; w_php_app_ip="${WIN_PHP_APP_IP:-${PHP_APP_IP:-}}"; w_php_db_ip="${WIN_PHP_DB_IP:-${PHP_DB_IP:-}}"
        fi

        [[ "$DEPLOY_JAVA" == "true" ]] && cat >> "$inv_file" <<EOF

[win_java_frontend]
$w_java_fe_ip

[win_java_appserver]
$w_java_app_ip

[win_java_database]
$w_java_db_ip
EOF
        [[ "$DEPLOY_DOTNET" == "true" ]] && cat >> "$inv_file" <<EOF

[win_dotnet_frontend]
$w_dotnet_fe_ip

[win_dotnet_appserver]
$w_dotnet_app_ip

[win_dotnet_database]
$w_dotnet_db_ip
EOF
        [[ "$DEPLOY_PHP" == "true" ]] && cat >> "$inv_file" <<EOF

[win_php_frontend]
$w_php_fe_ip

[win_php_appserver]
$w_php_app_ip

[win_php_database]
$w_php_db_ip
EOF
        {
            echo ""
            echo "[win_frontends:children]"
            [[ "$DEPLOY_JAVA" == "true" ]] && echo "win_java_frontend"
            [[ "$DEPLOY_DOTNET" == "true" ]] && echo "win_dotnet_frontend"
            [[ "$DEPLOY_PHP" == "true" ]] && echo "win_php_frontend"
            echo ""
            echo "[win_appservers:children]"
            [[ "$DEPLOY_JAVA" == "true" ]] && echo "win_java_appserver"
            [[ "$DEPLOY_DOTNET" == "true" ]] && echo "win_dotnet_appserver"
            [[ "$DEPLOY_PHP" == "true" ]] && echo "win_php_appserver"
            echo ""
            echo "[win_databases:children]"
            [[ "$DEPLOY_JAVA" == "true" ]] && echo "win_java_database"
            [[ "$DEPLOY_DOTNET" == "true" ]] && echo "win_dotnet_database"
            [[ "$DEPLOY_PHP" == "true" ]] && echo "win_php_database"
            echo ""
            echo "[win_servers_3tier:children]"
            echo "win_frontends"
            echo "win_appservers"
            echo "win_databases"
            echo ""
            echo "[win_servers_3tier:vars]"
            echo "ansible_connection=winrm"
            echo "ansible_winrm_transport=ntlm"
            echo "ansible_winrm_scheme=http"
            echo "ansible_user=Administrator"
            echo "ansible_password=$WIN_ADMIN_PASS"
            echo "ansible_port=5985"
            echo "ansible_become=false"
        } >> "$inv_file"
    fi

    step "Created: ansible/inventory/hosts.ini"
}

# ---------------------------------------------------------------------------
run_terraform() {
    header "Phase 1 — Provisioning VMs on vSphere (Terraform) [$DEPLOY_MODE]"
    pushd "$TF_DIR" > /dev/null

    step "terraform init ..."
    terraform init -input=false

    step "Selecting workspace: $DEPLOY_MODE ..."
    terraform workspace select -or-create "$DEPLOY_MODE"

    # Merge deploy flags with existing state — never destroy apps from prior runs
    local existing_resources
    existing_resources=$(terraform state list 2>/dev/null || echo "")
    if [[ -n "$existing_resources" ]]; then
        step "Existing VMs detected in workspace — merging deploy flags to preserve them"
        local tf_java="$DEPLOY_JAVA" tf_dotnet="$DEPLOY_DOTNET" tf_php="$DEPLOY_PHP"
        if echo "$existing_resources" | grep -q "java"; then
            tf_java="true"
        fi
        if echo "$existing_resources" | grep -q "dotnet"; then
            tf_dotnet="true"
        fi
        if echo "$existing_resources" | grep -q "php"; then
            tf_php="true"
        fi
        if [[ "$tf_java" != "$DEPLOY_JAVA" || "$tf_dotnet" != "$DEPLOY_DOTNET" || "$tf_php" != "$DEPLOY_PHP" ]]; then
            step "Adjusted: deploy_java=$tf_java deploy_dotnet=$tf_dotnet deploy_php=$tf_php"
            # Rewrite tfvars with merged flags
            sed -i "s/^deploy_java   = .*/deploy_java   = $tf_java/" terraform.tfvars
            sed -i "s/^deploy_dotnet = .*/deploy_dotnet = $tf_dotnet/" terraform.tfvars
            sed -i "s/^deploy_php    = .*/deploy_php    = $tf_php/" terraform.tfvars

            # Also restore IPs from state for stacks being preserved but not selected
            # This guards against IPs defaulting when user only deploys one stack
            if [[ "$tf_java" == "true" && "$DEPLOY_JAVA" != "true" ]]; then
                local ip
                for vm_key in java-fe java-app java-db; do
                    ip=$(terraform state show "vsphere_virtual_machine.vm_3tier[\"$vm_key\"]" 2>/dev/null \
                         | grep 'default_ip_address' | head -1 | sed 's/.*= *"\(.*\)"/\1/' || true)
                    if [[ -n "$ip" ]]; then
                        local tf_var="${vm_key//-/_}_ip"   # java-fe -> java_fe_ip
                        sed -i "s/^${tf_var} .* = .*/${tf_var} = \"${ip}\"/" terraform.tfvars
                        step "  Preserved $vm_key IP: $ip"
                    fi
                done
            fi
            if [[ "$tf_dotnet" == "true" && "$DEPLOY_DOTNET" != "true" ]]; then
                local ip
                for vm_key in dotnet-fe dotnet-app dotnet-db; do
                    ip=$(terraform state show "vsphere_virtual_machine.vm_3tier[\"$vm_key\"]" 2>/dev/null \
                         | grep 'default_ip_address' | head -1 | sed 's/.*= *"\(.*\)"/\1/' || true)
                    if [[ -n "$ip" ]]; then
                        local tf_var="${vm_key//-/_}_ip"
                        sed -i "s/^${tf_var} .* = .*/${tf_var} = \"${ip}\"/" terraform.tfvars
                        step "  Preserved $vm_key IP: $ip"
                    fi
                done
            fi
            if [[ "$tf_php" == "true" && "$DEPLOY_PHP" != "true" ]]; then
                local ip
                for vm_key in php-fe php-app php-db; do
                    ip=$(terraform state show "vsphere_virtual_machine.vm_3tier[\"$vm_key\"]" 2>/dev/null \
                         | grep 'default_ip_address' | head -1 | sed 's/.*= *"\(.*\)"/\1/' || true)
                    if [[ -n "$ip" ]]; then
                        local tf_var="${vm_key//-/_}_ip"
                        sed -i "s/^${tf_var} .* = .*/${tf_var} = \"${ip}\"/" terraform.tfvars
                        step "  Preserved $vm_key IP: $ip"
                    fi
                done
            fi
        fi

        # ── Preserve hostnames & domain from state for ALL existing VMs ──
        # The vSphere provider treats host_name and domain inside
        # clone.customize as ForceNew — any change destroys & recreates the VM.
        # Pull the actual values from state and patch tfvars so Terraform
        # sees no diff on these immutable attributes.
        _preserve_vm_attrs() {
            local resource="$1" vm_key="$2" prefix="$3"
            local state_block
            state_block=$(terraform state show "${resource}[\"${vm_key}\"]" 2>/dev/null || true)
            [[ -z "$state_block" ]] && return

            # Extract hostname (= the VM name vSphere used at clone time)
            local cur_name
            cur_name=$(echo "$state_block" | grep '^\s*name\s*=' | head -1 \
                       | sed 's/.*= *"\(.*\)"/\1/')
            if [[ -n "$cur_name" ]]; then
                local tf_var="${prefix}${vm_key//-/_}_hostname"
                sed -i "s|^${tf_var} .*=.*|${tf_var} = \"${cur_name}\"|" terraform.tfvars
                step "  Preserved $vm_key hostname: $cur_name"
            fi

            # Extract IP
            local cur_ip
            cur_ip=$(echo "$state_block" | grep 'default_ip_address' | head -1 \
                     | sed 's/.*= *"\(.*\)"/\1/')
            if [[ -n "$cur_ip" ]]; then
                local tf_var="${prefix}${vm_key//-/_}_ip"
                sed -i "s|^${tf_var} .*=.*|${tf_var} = \"${cur_ip}\"|" terraform.tfvars
                step "  Preserved $vm_key IP: $cur_ip"
            fi
        }

        # Preserve domain from state (also ForceNew in linux_options)
        local state_domain
        local first_vm
        first_vm=$(echo "$existing_resources" | grep 'vm_3tier\[\|vm\[' | head -1 || true)
        if [[ -n "$first_vm" ]]; then
            state_domain=$(terraform state show "$first_vm" 2>/dev/null \
                          | grep '^\s*domain\s*=' | head -1 \
                          | sed 's/.*= *"\(.*\)"/\1/' || true)
            if [[ -n "$state_domain" ]]; then
                sed -i "s|^vm_domain .*=.*|vm_domain              = \"${state_domain}\"|" terraform.tfvars
                step "  Preserved domain: $state_domain"
            fi
        fi

        # Linux 3-tier VMs
        if [[ "$DEPLOY_MODE" == "linux-3tier" ]]; then
            for vm_key in java-fe java-app java-db dotnet-fe dotnet-app dotnet-db php-fe php-app php-db; do
                echo "$existing_resources" | grep -q "vm_3tier\[\"${vm_key}\"\]" || continue
                _preserve_vm_attrs "vsphere_virtual_machine.vm_3tier" "$vm_key" ""
            done
        fi

        # Windows 3-tier VMs
        if [[ "$DEPLOY_MODE" == "windows-3tier" ]]; then
            for vm_key in win-java-fe win-java-app win-java-db win-dotnet-fe win-dotnet-app win-dotnet-db win-php-fe win-php-app win-php-db; do
                echo "$existing_resources" | grep -q "win_vm_3tier\[\"${vm_key}\"\]" || continue
                _preserve_vm_attrs "vsphere_virtual_machine.win_vm_3tier" "$vm_key" ""
            done
        fi

        # Linux single-VM
        if [[ "$DEPLOY_MODE" == "linux" ]]; then
            for vm_key in java-vm dotnet-vm php-vm; do
                echo "$existing_resources" | grep -q "vm\[\"${vm_key}\"\]" || continue
                _preserve_vm_attrs "vsphere_virtual_machine.vm" "$vm_key" ""
            done
        fi

        # Windows single-VM (shares java_vm/dotnet_vm/php_vm hostname vars)
        if [[ "$DEPLOY_MODE" == "windows" ]]; then
            for vm_key in win-java-vm win-dotnet-vm win-php-vm; do
                echo "$existing_resources" | grep -q "win_vm\[\"${vm_key}\"\]" || continue
                local state_block
                state_block=$(terraform state show "vsphere_virtual_machine.win_vm[\"${vm_key}\"]" 2>/dev/null || true)
                [[ -z "$state_block" ]] && continue
                local cur_name
                cur_name=$(echo "$state_block" | grep '^\s*name\s*=' | head -1 | sed 's/.*= *"\(.*\)"/\1/')
                if [[ -n "$cur_name" ]]; then
                    # win-java-vm -> java_vm_hostname (strip win- prefix)
                    local tf_var="${vm_key#win-}"; tf_var="${tf_var//-/_}_hostname"
                    sed -i "s|^${tf_var} .*=.*|${tf_var} = \"${cur_name}\"|" terraform.tfvars
                    step "  Preserved $vm_key hostname: $cur_name"
                fi
                local cur_ip
                cur_ip=$(echo "$state_block" | grep 'default_ip_address' | head -1 | sed 's/.*= *"\(.*\)"/\1/')
                if [[ -n "$cur_ip" ]]; then
                    local tf_var="${vm_key#win-}"; tf_var="${tf_var//-/_}_ip"
                    sed -i "s|^${tf_var} .*=.*|${tf_var} = \"${cur_ip}\"|" terraform.tfvars
                    step "  Preserved $vm_key IP: $cur_ip"
                fi
            done
        fi
    fi

    step "terraform plan ..."
    terraform plan -out=tfplan

    step "terraform apply ..."
    terraform apply -auto-approve tfplan

    step "VMs created. Waiting 60s for SSH readiness..."
    sleep 60

    popd > /dev/null
}

run_ansible() {
    header "Phase 2 — Deploying Applications (Ansible) [$DEPLOY_MODE]"
    pushd "$ANSIBLE_DIR" > /dev/null

    # Fix directory permissions so ansible.cfg is loaded
    chmod 755 "$ANSIBLE_DIR" 2>/dev/null || true
    export ANSIBLE_CONFIG="$ANSIBLE_DIR/ansible.cfg"

    # Only install collections that are not already present
    install_galaxy_if_missing() {
        local missing=()
        for col in "$@"; do
            if ! ansible-galaxy collection list 2>/dev/null | grep -q "$col"; then
                missing+=("$col")
            fi
        done
        if [[ ${#missing[@]} -gt 0 ]]; then
            step "Installing Ansible Galaxy collections: ${missing[*]}"
            ansible-galaxy collection install "${missing[@]}"
        else
            step "Ansible Galaxy collections already installed — skipping"
        fi
    }
    if [[ "$DEPLOY_MODE" == "linux" || "$DEPLOY_MODE" == "linux-3tier" ]]; then
        install_galaxy_if_missing community.postgresql community.mysql community.general
    else
        install_galaxy_if_missing ansible.windows community.general
    fi

    # Build --limit to only target the stacks the user selected (not merged ones)
    local limit_groups=""
    if [[ "$DEPLOY_MODE" == "linux-3tier" ]]; then
        [[ "$DEPLOY_JAVA" == "true" ]]   && limit_groups="${limit_groups:+$limit_groups:}java_frontend:java_appserver:java_database"
        [[ "$DEPLOY_DOTNET" == "true" ]] && limit_groups="${limit_groups:+$limit_groups:}dotnet_frontend:dotnet_appserver:dotnet_database"
        [[ "$DEPLOY_PHP" == "true" ]]    && limit_groups="${limit_groups:+$limit_groups:}php_frontend:php_appserver:php_database"
    elif [[ "$DEPLOY_MODE" == "windows-3tier" ]]; then
        [[ "$DEPLOY_JAVA" == "true" ]]   && limit_groups="${limit_groups:+$limit_groups:}win_java_frontend:win_java_appserver:win_java_database"
        [[ "$DEPLOY_DOTNET" == "true" ]] && limit_groups="${limit_groups:+$limit_groups:}win_dotnet_frontend:win_dotnet_appserver:win_dotnet_database"
        [[ "$DEPLOY_PHP" == "true" ]]    && limit_groups="${limit_groups:+$limit_groups:}win_php_frontend:win_php_appserver:win_php_database"
    elif [[ "$DEPLOY_MODE" == "linux" ]]; then
        [[ "$DEPLOY_JAVA" == "true" ]]   && limit_groups="${limit_groups:+$limit_groups:}java_servers"
        [[ "$DEPLOY_DOTNET" == "true" ]] && limit_groups="${limit_groups:+$limit_groups:}dotnet_servers"
        [[ "$DEPLOY_PHP" == "true" ]]    && limit_groups="${limit_groups:+$limit_groups:}php_servers"
    elif [[ "$DEPLOY_MODE" == "windows" ]]; then
        [[ "$DEPLOY_JAVA" == "true" ]]   && limit_groups="${limit_groups:+$limit_groups:}win_java_servers"
        [[ "$DEPLOY_DOTNET" == "true" ]] && limit_groups="${limit_groups:+$limit_groups:}win_dotnet_servers"
        [[ "$DEPLOY_PHP" == "true" ]]    && limit_groups="${limit_groups:+$limit_groups:}win_php_servers"
    fi
    local limit_arg=""
    if [[ -n "$limit_groups" ]]; then
        limit_arg="--limit $limit_groups"
        step "Ansible will only target selected stacks: $limit_groups"
    fi

    # Select the correct master playbook for the deploy mode
    local master_playbook="site.yml"
    case "$DEPLOY_MODE" in
        linux-3tier)   master_playbook="playbooks/3tier/site-3tier.yml" ;;
        windows-3tier) master_playbook="playbooks/3tier/site-3tier-win.yml" ;;
    esac

    local max_retries=3
    local attempt=1
    local retry_file=""
    # Ansible generates retry files based on the playbook basename (e.g. site-3tier.retry)
    local retry_name
    retry_name="$(basename "${master_playbook}" .yml).retry"

    # Remove stale retry files from previous runs
    rm -f *.retry 2>/dev/null || true

    while [[ $attempt -le $max_retries ]]; do
        if [[ $attempt -eq 1 && -z "$retry_file" ]]; then
            step "Running master playbook (attempt $attempt/$max_retries)..."
            ansible-playbook -i inventory/hosts.ini "$master_playbook" -v $limit_arg && break
        else
            step "Retrying failed tasks (attempt $attempt/$max_retries)..."
            ansible-playbook -i inventory/hosts.ini "$master_playbook" -v --limit "@$retry_name" && break
        fi

        if [[ -f "$retry_name" ]]; then
            retry_file="$retry_name"
            warn "Attempt $attempt failed. Hosts with failures: $(cat "$retry_name")"
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
        if [[ -f "$retry_name" ]]; then
            echo -e "    ${GR}ansible-playbook -i inventory/hosts.ini $master_playbook -v --limit @$retry_name${NC}"
        else
            echo -e "    ${GR}ansible-playbook -i inventory/hosts.ini $master_playbook -v${NC}"
        fi
        popd > /dev/null
        return 1
    fi

    popd > /dev/null
}

run_verify() {
    header "Phase 3 — Verification ($DEPLOY_MODE)"
    echo ""
    local checks=()
    if [[ "$DEPLOY_MODE" == "linux" ]]; then
        [[ "$DEPLOY_JAVA" == "true" ]]   && checks+=("Java PetClinic|$JAVA_IP|8080")
        [[ "$DEPLOY_DOTNET" == "true" ]] && checks+=(".NET MVC App|$DOTNET_IP|80")
        [[ "$DEPLOY_PHP" == "true" ]]    && checks+=("PHP Laravel|$PHP_IP|80")
    elif [[ "$DEPLOY_MODE" == "windows" ]]; then
        [[ "$DEPLOY_JAVA" == "true" ]]   && checks+=("Win Java PetClinic|$JAVA_IP|8080")
        [[ "$DEPLOY_DOTNET" == "true" ]] && checks+=("Win .NET IIS App|$DOTNET_IP|80")
        [[ "$DEPLOY_PHP" == "true" ]]    && checks+=("Win PHP Laravel|$PHP_IP|80")
    elif [[ "$DEPLOY_MODE" == "linux-3tier" ]]; then
        [[ "$DEPLOY_JAVA" == "true" ]] && checks+=(
            "Java Frontend (Angular)|$JAVA_FE_IP|80"
            "Java App Server (REST)|$JAVA_APP_IP|9966"
            "Java Database (PostgreSQL)|$JAVA_DB_IP|5432"
        )
        [[ "$DEPLOY_DOTNET" == "true" ]] && checks+=(
            ".NET Frontend (Nginx)|$DOTNET_FE_IP|80"
            ".NET App Server (ASP.NET)|$DOTNET_APP_IP|5000"
            ".NET Database (SQL Server)|$DOTNET_DB_IP|1433"
        )
        [[ "$DEPLOY_PHP" == "true" ]] && checks+=(
            "PHP Frontend (Nginx)|$PHP_FE_IP|80"
            "PHP App Server (Laravel)|$PHP_APP_IP|8000"
            "PHP Database (MySQL)|$PHP_DB_IP|3306"
        )
    elif [[ "$DEPLOY_MODE" == "windows-3tier" ]]; then
        [[ "$DEPLOY_JAVA" == "true" ]] && checks+=(
            "Win Java Frontend (IIS+ARR)|$JAVA_FE_IP|80"
            "Win Java App Server (NSSM)|$JAVA_APP_IP|9966"
            "Win Java Database (PostgreSQL)|$JAVA_DB_IP|5432"
        )
        [[ "$DEPLOY_DOTNET" == "true" ]] && checks+=(
            "Win .NET Frontend (IIS+ARR)|$DOTNET_FE_IP|80"
            "Win .NET App Server (Kestrel)|$DOTNET_APP_IP|5000"
            "Win .NET Database (SQL Server)|$DOTNET_DB_IP|1433"
        )
        [[ "$DEPLOY_PHP" == "true" ]] && checks+=(
            "Win PHP Frontend (IIS+ARR)|$PHP_FE_IP|80"
            "Win PHP App Server (Laravel)|$PHP_APP_IP|8000"
            "Win PHP Database (MySQL)|$PHP_DB_IP|3306"
        )
    fi
    for pair in "${checks[@]}"; do
        IFS='|' read -r name ip port <<< "$pair"
        if timeout 3 bash -c "echo >/dev/tcp/$ip/$port" 2>/dev/null; then
            echo -e "    ${G}[OK]${NC}   $name  http://$ip:$port"
        else
            echo -e "    ${Y}[WAIT]${NC} $name  http://$ip:$port — may still be starting"
        fi
    done

    header "Deployment Complete ($DEPLOY_MODE)!"
    echo -e "  Access your apps:"
    if [[ "$DEPLOY_MODE" == "linux" || "$DEPLOY_MODE" == "windows" ]]; then
        [[ "$DEPLOY_JAVA" == "true" ]]   && echo -e "    ${C}Java PetClinic:${NC}  http://$JAVA_IP:8080"
        [[ "$DEPLOY_DOTNET" == "true" ]] && echo -e "    ${C}.NET App:${NC}        http://$DOTNET_IP"
        [[ "$DEPLOY_PHP" == "true" ]]    && echo -e "    ${C}PHP Laravel:${NC}     http://$PHP_IP"
    elif [[ "$DEPLOY_MODE" == *"3tier"* ]]; then
        [[ "$DEPLOY_JAVA" == "true" ]]   && echo -e "    ${C}Java Frontend:${NC}   http://$JAVA_FE_IP"
        [[ "$DEPLOY_DOTNET" == "true" ]] && echo -e "    ${C}.NET Frontend:${NC}   http://$DOTNET_FE_IP"
        [[ "$DEPLOY_PHP" == "true" ]]    && echo -e "    ${C}PHP Frontend:${NC}    http://$PHP_FE_IP"
    fi
    echo ""
    echo -e "  ${G}All VMs ready for Azure Migrate discovery.${NC}"
    echo -e "  ${G}Point appliance at vCenter: $VSPHERE_SERVER${NC}"
    echo ""
}

# ---------------------------------------------------------------------------
run_destroy() {
    header "Destroying VMs (Terraform Destroy)"
    pushd "$TF_DIR" > /dev/null

    # Determine which workspaces to destroy
    local modes=()
    if [[ ${#DEPLOY_MODES[@]} -gt 0 ]]; then
        modes=("${DEPLOY_MODES[@]}")
    else
        load_previous
        if [[ "$PREV_OS_CHOICE" == "both" ]]; then
            if [[ "$PREV_ARCH_CHOICE" == "3tier" ]]; then
                modes=("linux-3tier" "windows-3tier")
            else
                modes=("linux" "windows")
            fi
        else
            modes=("${PREV_DEPLOY_MODE:-linux}")
        fi
    fi

    step "terraform init ..."
    terraform init -input=false

    for ws in "${modes[@]}"; do
        if ! terraform workspace select "$ws" 2>/dev/null; then
            warn "Workspace '$ws' not found. Skipping."
            continue
        fi

        step "terraform destroy (workspace: $ws) ..."
        terraform destroy -auto-approve
        step "VMs destroyed in workspace: $ws"
    done

    popd > /dev/null
}

run_ansible_resume() {
    header "Phase 2 — Resuming Ansible (all hosts, idempotent)"
    pushd "$ANSIBLE_DIR" > /dev/null

    # Fix directory permissions so ansible.cfg is loaded
    chmod 755 "$ANSIBLE_DIR" 2>/dev/null || true
    export ANSIBLE_CONFIG="$ANSIBLE_DIR/ansible.cfg"

    if [[ -f "site.retry" ]]; then
        step "Previous retry file found with failed hosts: $(cat site.retry)"
        rm -f site.retry
    fi

    step "Running full playbook (idempotent — skips completed tasks)..."
    # Select the correct master playbook for the deploy mode
    local master_playbook="site.yml"
    case "$DEPLOY_MODE" in
        linux-3tier)   master_playbook="playbooks/3tier/site-3tier.yml" ;;
        windows-3tier) master_playbook="playbooks/3tier/site-3tier-win.yml" ;;
    esac
    ansible-playbook -i inventory/hosts.ini "$master_playbook" -v

    popd > /dev/null
}

# ---------------------------------------------------------------------------
# Helper: parse inventory and list VMs by group type
show_inventory_vms() {
    local inv_file="$ANSIBLE_DIR/inventory/hosts.ini"
    if [[ ! -f "$inv_file" ]]; then
        echo -e "  ${R}No inventory found at $inv_file${NC}"
        echo -e "  ${R}Run the wizard or Terraform first to generate inventory.${NC}"
        return 1
    fi

    local linux_vms="" windows_vms="" current_section="" line host ip
    while IFS= read -r line; do
        # Skip comments and blank lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// /}" ]] && continue
        # Track section headers
        if [[ "$line" =~ ^\[(.+)\]$ ]]; then
            current_section="${BASH_REMATCH[1]}"
            continue
        fi
        # Skip :children and :vars meta-sections
        [[ "$current_section" == *:children* || "$current_section" == *:vars* ]] && continue
        # Extract host IP (first token on the line)
        host="${line%% *}"
        [[ -z "$host" ]] && continue
        # Classify as Linux or Windows based on section name prefix
        if [[ "$current_section" == win_* ]]; then
            windows_vms+="    $current_section: $host\n"
        else
            linux_vms+="    $current_section: $host\n"
        fi
    done < "$inv_file"

    local has_linux=false has_windows=false
    if [[ -n "$linux_vms" ]]; then
        has_linux=true
        echo -e "  ${C}--- Linux VMs ---${NC}"
        echo -e "$linux_vms"
    fi
    if [[ -n "$windows_vms" ]]; then
        has_windows=true
        echo -e "  ${C}--- Windows VMs ---${NC}"
        echo -e "$windows_vms"
    fi
    if ! $has_linux && ! $has_windows; then
        echo -e "  ${R}No VMs found in inventory.${NC}"
        return 1
    fi

    # Export for caller
    DNS_HAS_LINUX=$has_linux
    DNS_HAS_WINDOWS=$has_windows
}

run_dns_register() {
    header "DNS Registration — Register VMs in Windows DNS"
    pushd "$ANSIBLE_DIR" > /dev/null

    chmod 755 "$ANSIBLE_DIR" 2>/dev/null || true
    export ANSIBLE_CONFIG="$ANSIBLE_DIR/ansible.cfg"

    # Load previous DNS registration settings if available
    local dns_conf="$ANSIBLE_DIR/.dnsregister.conf"
    local prev_dns_srv="" prev_dns_zone="" prev_dns_user="" prev_dns_scope=""
    if [[ -f "$dns_conf" ]]; then
        step "Found previous DNS registration config — loading as defaults"
        prev_dns_srv=$(grep '^DNS_SERVER=' "$dns_conf" 2>/dev/null | cut -d= -f2-)
        prev_dns_zone=$(grep '^DNS_ZONE=' "$dns_conf" 2>/dev/null | cut -d= -f2-)
        prev_dns_user=$(grep '^DNS_USER=' "$dns_conf" 2>/dev/null | cut -d= -f2-)
        prev_dns_scope=$(grep '^DNS_SCOPE=' "$dns_conf" 2>/dev/null | cut -d= -f2-)
    fi

    # Show discovered VMs from inventory
    echo ""
    echo -e "  ${Y}Discovered VMs from inventory:${NC}"
    echo ""
    if ! show_inventory_vms; then
        popd > /dev/null
        return 1
    fi

    # Prompt for DNS server address
    local def_dns="${prev_dns_srv:-${VM_DNS%%,*}}"
    def_dns="${def_dns:-10.1.3.1}"
    read -rp "  DNS Server IP [$def_dns]: " dns_srv
    dns_srv="${dns_srv:-$def_dns}"

    # Prompt for DNS zone
    local def_zone="${prev_dns_zone:-${VM_DOMAIN:-lab.local}}"
    read -rp "  DNS Zone [$def_zone]: " dns_z
    dns_z="${dns_z:-$def_zone}"

    # Prompt for domain admin credentials (required for AD-integrated DNS)
    echo ""
    echo -e "  ${Y}Domain admin credentials (required to update DNS records):${NC}"
    local def_user="${prev_dns_user:-Administrator}"
    read -rp "  Domain admin username [$def_user]: " dns_admin_user
    dns_admin_user="${dns_admin_user:-$def_user}"
    read -srp "  Domain admin password: " dns_admin_pass
    echo ""
    if [[ -z "$dns_admin_pass" ]]; then
        err "Password cannot be empty"; popd > /dev/null; return 1
    fi

    echo ""
    echo -e "  ${Y}Which VMs to register?${NC}"
    if $DNS_HAS_LINUX; then
        echo -e "    ${G}1)${NC} Linux only"
    fi
    if $DNS_HAS_WINDOWS; then
        echo -e "    ${G}2)${NC} Windows only"
    fi
    local def_scope="${prev_dns_scope:-}"
    if $DNS_HAS_LINUX && $DNS_HAS_WINDOWS; then
        echo -e "    ${G}3)${NC} Both (all deployed VMs)"
        def_scope="${def_scope:-3}"
        read -rp "  Choice [$def_scope]: " dns_choice
        dns_choice="${dns_choice:-$def_scope}"
    elif $DNS_HAS_LINUX; then
        def_scope="${def_scope:-1}"
        read -rp "  Choice [$def_scope]: " dns_choice
        dns_choice="${dns_choice:-$def_scope}"
    else
        def_scope="${def_scope:-2}"
        read -rp "  Choice [$def_scope]: " dns_choice
        dns_choice="${dns_choice:-$def_scope}"
    fi

    local playbook=""
    case "$dns_choice" in
        1) playbook="playbooks/dns-register-linux.yml" ;;
        2) playbook="playbooks/dns-register-windows.yml" ;;
        3) playbook="playbooks/dns-register-all.yml" ;;
        *) err "Invalid choice"; popd > /dev/null; return 1 ;;
    esac

    # Save DNS registration settings for next run (passwords are NEVER saved)
    cat > "$dns_conf" <<EOF
# DNS Registration settings — auto-saved by setup-interactive.sh
# Passwords are never saved.
DNS_SERVER=$dns_srv
DNS_ZONE=$dns_z
DNS_USER=$dns_admin_user
DNS_SCOPE=$dns_choice
EOF

    step "Registering VMs — DNS server=$dns_srv zone=$dns_z user=$dns_admin_user"
    ansible-playbook -i inventory/hosts.ini "$playbook" \
        -e "dns_server=$dns_srv" -e "dns_zone=$dns_z" \
        -e "dns_admin_user=$dns_admin_user" -e "dns_admin_password=$dns_admin_pass" -v

    popd > /dev/null
}

# ---------------------------------------------------------------------------
run_domain_join() {
    header "Domain Join — Join VMs to Active Directory"
    echo -e "  ${C}This will join VMs to an AD domain.${NC}"
    echo -e "  ${C}DNS registration happens automatically with domain join.${NC}"
    echo ""
    pushd "$ANSIBLE_DIR" > /dev/null

    chmod 755 "$ANSIBLE_DIR" 2>/dev/null || true
    export ANSIBLE_CONFIG="$ANSIBLE_DIR/ansible.cfg"

    # Load previous domain join settings if available
    local dj_conf="$ANSIBLE_DIR/.domainjoin.conf"
    local prev_dj_domain="" prev_dj_dc="" prev_dj_user="" prev_dj_scope=""
    if [[ -f "$dj_conf" ]]; then
        step "Found previous domain join config — loading as defaults"
        prev_dj_domain=$(grep '^DJ_DOMAIN=' "$dj_conf" 2>/dev/null | cut -d= -f2-)
        prev_dj_dc=$(grep '^DJ_DC=' "$dj_conf" 2>/dev/null | cut -d= -f2-)
        prev_dj_user=$(grep '^DJ_USER=' "$dj_conf" 2>/dev/null | cut -d= -f2-)
        prev_dj_scope=$(grep '^DJ_SCOPE=' "$dj_conf" 2>/dev/null | cut -d= -f2-)
    fi

    # Show discovered VMs from inventory
    echo -e "  ${Y}Discovered VMs from inventory:${NC}"
    echo ""
    if ! show_inventory_vms; then
        popd > /dev/null
        return 1
    fi

    # Prompt for AD domain (use saved value, fall back to VM_DOMAIN)
    local def_domain="${prev_dj_domain:-${VM_DOMAIN:-lab.local}}"
    read -rp "  AD Domain to join [$def_domain]: " ad_domain
    ad_domain="${ad_domain:-$def_domain}"

    # Prompt for DNS server (domain controller)
    local def_dc="${prev_dj_dc:-${VM_DNS%%,*}}"
    def_dc="${def_dc:-10.1.3.1}"
    read -rp "  Domain Controller / DNS Server IP [$def_dc]: " dc_ip
    dc_ip="${dc_ip:-$def_dc}"

    # Prompt for domain admin credentials
    echo ""
    echo -e "  ${Y}Domain admin credentials (must have permission to join machines):${NC}"
    local def_user="${prev_dj_user:-Administrator}"
    read -rp "  Domain admin username [$def_user]: " ad_user
    ad_user="${ad_user:-$def_user}"
    read -srp "  Domain admin password: " ad_pass
    echo ""
    if [[ -z "$ad_pass" ]]; then
        err "Password cannot be empty"; popd > /dev/null; return 1
    fi

    echo ""
    echo -e "  ${Y}Which VMs to join to ${C}${ad_domain}${Y}?${NC}"
    if $DNS_HAS_LINUX; then
        echo -e "    ${G}1)${NC} Linux only"
    fi
    if $DNS_HAS_WINDOWS; then
        echo -e "    ${G}2)${NC} Windows only"
    fi
    local def_scope="${prev_dj_scope:-}"
    if $DNS_HAS_LINUX && $DNS_HAS_WINDOWS; then
        echo -e "    ${G}3)${NC} Both (all deployed VMs)"
        def_scope="${def_scope:-3}"
        read -rp "  Choice [$def_scope]: " dj_choice
        dj_choice="${dj_choice:-$def_scope}"
    elif $DNS_HAS_LINUX; then
        def_scope="${def_scope:-1}"
        read -rp "  Choice [$def_scope]: " dj_choice
        dj_choice="${dj_choice:-$def_scope}"
    else
        def_scope="${def_scope:-2}"
        read -rp "  Choice [$def_scope]: " dj_choice
        dj_choice="${dj_choice:-$def_scope}"
    fi

    local playbook=""
    case "$dj_choice" in
        1) playbook="playbooks/domain-join-linux.yml" ;;
        2) playbook="playbooks/domain-join-windows.yml" ;;
        3) playbook="playbooks/domain-join-all.yml" ;;
        *) err "Invalid choice"; popd > /dev/null; return 1 ;;
    esac

    # Save domain join settings for next run (passwords are NEVER saved)
    cat > "$dj_conf" <<EOF
# Domain Join settings — auto-saved by setup-interactive.sh
# Passwords are never saved.
DJ_DOMAIN=$ad_domain
DJ_DC=$dc_ip
DJ_USER=$ad_user
DJ_SCOPE=$dj_choice
EOF

    # Derive retry file path from playbook name
    local retry_file="${ANSIBLE_DIR}/${playbook%.yml}.retry"

    step "Joining VMs to domain=$ad_domain DC=$dc_ip user=$ad_user"
    local rc=0
    ansible-playbook -i inventory/hosts.ini "$playbook" \
        -e "ad_domain=$ad_domain" -e "dns_server=$dc_ip" \
        -e "ad_admin_user=$ad_user" -e "ad_admin_password=$ad_pass" -v || rc=$?

    # Retry loop — keep offering to resume from failed hosts
    while [[ $rc -ne 0 && -f "$retry_file" ]]; do
        echo ""
        echo -e "  ${R}Domain join failed on some hosts.${NC}"
        echo -e "  ${Y}Retry file: ${retry_file}${NC}"
        echo -e "  ${Y}Failed hosts:${NC}"
        sed 's/^/    /' "$retry_file"
        echo ""
        read -rp "  Resume domain join for failed hosts? (y/n) [y]: " resume
        resume="${resume:-y}"
        if [[ "${resume,,}" != "y" ]]; then
            echo -e "  ${C}Skipping retry. You can re-run with: --domainjoin${NC}"
            break
        fi
        echo ""
        step "Resuming domain join for failed hosts..."
        rc=0
        ansible-playbook -i inventory/hosts.ini "$playbook" \
            --limit "@${retry_file}" \
            -e "ad_domain=$ad_domain" -e "dns_server=$dc_ip" \
            -e "ad_admin_user=$ad_user" -e "ad_admin_password=$ad_pass" -v || rc=$?
    done

    if [[ $rc -eq 0 ]]; then
        echo -e "  ${G}Domain join completed successfully.${NC}"
    fi

    popd > /dev/null
}

# ---------------------------------------------------------------------------
run_azmigrate_db() {
    header "Azure Migrate — Create DB Discovery Users"
    echo -e "  ${C}Creates least-privilege users on PostgreSQL and MySQL${NC}"
    echo -e "  ${C}for Azure Migrate database discovery & assessment.${NC}"
    echo ""
    pushd "$ANSIBLE_DIR" > /dev/null

    chmod 755 "$ANSIBLE_DIR" 2>/dev/null || true
    export ANSIBLE_CONFIG="$ANSIBLE_DIR/ansible.cfg"

    # Load previous settings if available
    local azmig_conf="$ANSIBLE_DIR/.azmigrate-db.conf"
    local prev_az_user="" prev_appliance_ip=""
    if [[ -f "$azmig_conf" ]]; then
        step "Found previous Azure Migrate DB config — loading as defaults"
        prev_az_user=$(grep '^AZ_MIGRATE_USER=' "$azmig_conf" 2>/dev/null | cut -d= -f2-)
        prev_appliance_ip=$(grep '^APPLIANCE_IP=' "$azmig_conf" 2>/dev/null | cut -d= -f2-)
    fi

    # Prompt for Azure Migrate user
    local def_user="${prev_az_user:-azmigrateuser}"
    read -rp "  Azure Migrate DB username [$def_user]: " az_user
    az_user="${az_user:-$def_user}"

    # Prompt for password
    read -srp "  Password for $az_user: " az_pass
    echo ""
    if [[ -z "$az_pass" ]]; then
        err "Password cannot be empty"; popd > /dev/null; return 1
    fi

    # Prompt for appliance IP (needed for pg_hba.conf)
    local def_ip="${prev_appliance_ip:-}"
    read -rp "  Azure Migrate appliance IP [$def_ip]: " app_ip
    app_ip="${app_ip:-$def_ip}"
    if [[ -z "$app_ip" ]]; then
        err "Appliance IP is required for PostgreSQL pg_hba.conf access"; popd > /dev/null; return 1
    fi

    # Prompt for DB admin passwords (needed for Windows VMs where peer auth isn't available)
    echo ""
    echo -e "  ${Y}Database admin passwords (needed for Windows DB VMs):${NC}"
    read -srp "  PostgreSQL superuser (postgres) password: " pg_admin_pass
    echo ""
    read -srp "  MySQL root password: " mysql_admin_pass
    echo ""

    # Save settings for next run (passwords are NEVER saved)
    cat > "$azmig_conf" <<EOF
# Azure Migrate DB settings — auto-saved by setup-interactive.sh
# Passwords are never saved.
AZ_MIGRATE_USER=$az_user
APPLIANCE_IP=$app_ip
EOF

    step "Creating Azure Migrate DB users — user=$az_user appliance=$app_ip"
    ansible-playbook -i inventory/hosts.ini playbooks/azure-migrate-db-users.yml \
        -e "az_migrate_user=$az_user" -e "az_migrate_password=$az_pass" \
        -e "appliance_ip=$app_ip" \
        -e "postgres_password=$pg_admin_pass" \
        -e "mysql_root_password=$mysql_admin_pass" -v

    local rc=$?
    if [[ $rc -eq 0 ]]; then
        echo ""
        echo -e "  ${G}Azure Migrate DB users created successfully.${NC}"
        echo -e "  ${C}Use these credentials in the Azure Migrate appliance:${NC}"
        echo -e "    ${Y}PostgreSQL:${NC} $az_user (port 5432)"
        echo -e "    ${Y}MySQL:${NC}      $az_user (port 3306)"
    else
        echo -e "  ${R}Some tasks failed. Check the output above.${NC}"
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

    # Handle --dns flag for standalone DNS registration of existing VMs
    if [[ "${1:-}" == "--dns" || "${1:-}" == "dns" ]]; then
        echo ""
        echo -e "  ${C}================================================================${NC}"
        echo -e "  ${C}     DNS Registration — Register Existing VMs${NC}"
        echo -e "  ${C}================================================================${NC}"
        echo ""
        check_prerequisites
        load_previous
        VM_DOMAIN="${PREV_VM_DOMAIN:-lab.local}"
        VM_DNS="${PREV_VM_DNS:-8.8.8.8}"

        # Restore deployment flags from previous config
        DEPLOY_JAVA="${PREV_DEPLOY_JAVA:-true}"
        DEPLOY_DOTNET="${PREV_DEPLOY_DOTNET:-true}"
        DEPLOY_PHP="${PREV_DEPLOY_PHP:-true}"
        SSH_USER="${PREV_SSH_USER:-ubuntu}"
        SSH_AUTH_METHOD="${PREV_SSH_AUTH_METHOD:-password}"
        SSH_KEY="${PREV_SSH_KEY:-}"

        # Discover ALL Terraform workspaces with state (don't rely on saved OS choice)
        pushd "$TF_DIR" > /dev/null
        terraform init -input=false > /dev/null 2>&1
        local all_workspaces
        all_workspaces=$(terraform workspace list 2>/dev/null | sed 's/[* ]//g' | grep -v '^default$' | grep -v '^$' || echo "")
        popd > /dev/null

        if [[ -z "$all_workspaces" ]]; then
            err "No Terraform workspaces found. Deploy VMs first."
            exit 1
        fi

        DEPLOY_MODES=()
        while IFS= read -r ws; do
            DEPLOY_MODES+=("$ws")
        done <<< "$all_workspaces"
        step "Found Terraform workspaces: ${DEPLOY_MODES[*]}"

        # Prompt for credentials based on discovered workspaces
        local need_linux=false need_windows=false
        for m in "${DEPLOY_MODES[@]}"; do
            [[ "$m" == linux* ]] && need_linux=true
            [[ "$m" == windows* ]] && need_windows=true
        done
        if $need_linux && [[ "$SSH_AUTH_METHOD" == "password" ]]; then
            prompt_secret "SSH password for $SSH_USER"; SSH_PASSWORD="$REPLY"
        fi
        if $need_windows; then
            prompt_secret "Windows Administrator password"; WIN_ADMIN_PASS="$REPLY"
        fi

        # Read Terraform state for all workspaces and rebuild combined inventory
        INVENTORY_INITIALIZED=""
        for mode in "${DEPLOY_MODES[@]}"; do
            DEPLOY_MODE="$mode"
            step "Reading Terraform state for workspace: $DEPLOY_MODE"
            pushd "$TF_DIR" > /dev/null
            terraform workspace select "$DEPLOY_MODE" 2>/dev/null || {
                warn "Terraform workspace '$DEPLOY_MODE' not found. Skipping."
                popd > /dev/null
                continue
            }
            if [[ "$DEPLOY_MODE" == *"3tier"* ]]; then
                if [[ "$DEPLOY_JAVA" == "true" ]]; then
                    JAVA_FE_IP="$(terraform output -json java_3tier_ips 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['frontend'])" 2>/dev/null || echo "")"
                    JAVA_APP_IP="$(terraform output -json java_3tier_ips 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['appserver'])" 2>/dev/null || echo "")"
                    JAVA_DB_IP="$(terraform output -json java_3tier_ips 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['database'])" 2>/dev/null || echo "")"
                fi
                if [[ "$DEPLOY_DOTNET" == "true" ]]; then
                    DOTNET_FE_IP="$(terraform output -json dotnet_3tier_ips 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['frontend'])" 2>/dev/null || echo "")"
                    DOTNET_APP_IP="$(terraform output -json dotnet_3tier_ips 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['appserver'])" 2>/dev/null || echo "")"
                    DOTNET_DB_IP="$(terraform output -json dotnet_3tier_ips 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['database'])" 2>/dev/null || echo "")"
                fi
                if [[ "$DEPLOY_PHP" == "true" ]]; then
                    PHP_FE_IP="$(terraform output -json php_3tier_ips 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['frontend'])" 2>/dev/null || echo "")"
                    PHP_APP_IP="$(terraform output -json php_3tier_ips 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['appserver'])" 2>/dev/null || echo "")"
                    PHP_DB_IP="$(terraform output -json php_3tier_ips 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['database'])" 2>/dev/null || echo "")"
                fi
            else
                [[ "$DEPLOY_JAVA" == "true" ]]   && JAVA_IP="$(terraform output -raw java_vm_ip 2>/dev/null || echo "")"
                [[ "$DEPLOY_DOTNET" == "true" ]] && DOTNET_IP="$(terraform output -raw dotnet_vm_ip 2>/dev/null || echo "")"
                [[ "$DEPLOY_PHP" == "true" ]]    && PHP_IP="$(terraform output -raw php_vm_ip 2>/dev/null || echo "")"
            fi
            popd > /dev/null

            # Append to inventory (INVENTORY_INITIALIZED flag handles first-write truncation)
            write_inventory
        done

        step "Inventory rebuilt from Terraform state"
        run_dns_register
        exit 0
    fi

    # Handle --domainjoin flag for standalone domain join of existing VMs
    if [[ "${1:-}" == "--domainjoin" || "${1:-}" == "domainjoin" ]]; then
        echo ""
        echo -e "  ${C}================================================================${NC}"
        echo -e "  ${C}     Domain Join — Join Existing VMs to AD Domain${NC}"
        echo -e "  ${C}================================================================${NC}"
        echo ""
        check_prerequisites
        load_previous
        VM_DOMAIN="${PREV_VM_DOMAIN:-lab.local}"
        VM_DNS="${PREV_VM_DNS:-8.8.8.8}"

        DEPLOY_JAVA="${PREV_DEPLOY_JAVA:-true}"
        DEPLOY_DOTNET="${PREV_DEPLOY_DOTNET:-true}"
        DEPLOY_PHP="${PREV_DEPLOY_PHP:-true}"
        SSH_USER="${PREV_SSH_USER:-ubuntu}"
        SSH_AUTH_METHOD="${PREV_SSH_AUTH_METHOD:-password}"
        SSH_KEY="${PREV_SSH_KEY:-}"

        pushd "$TF_DIR" > /dev/null
        terraform init -input=false > /dev/null 2>&1
        local all_workspaces
        all_workspaces=$(terraform workspace list 2>/dev/null | sed 's/[* ]//g' | grep -v '^default$' | grep -v '^$' || echo "")
        popd > /dev/null

        if [[ -z "$all_workspaces" ]]; then
            err "No Terraform workspaces found. Deploy VMs first."
            exit 1
        fi

        DEPLOY_MODES=()
        while IFS= read -r ws; do
            DEPLOY_MODES+=("$ws")
        done <<< "$all_workspaces"
        step "Found Terraform workspaces: ${DEPLOY_MODES[*]}"

        local need_linux=false need_windows=false
        for m in "${DEPLOY_MODES[@]}"; do
            [[ "$m" == linux* ]] && need_linux=true
            [[ "$m" == windows* ]] && need_windows=true
        done
        if $need_linux && [[ "$SSH_AUTH_METHOD" == "password" ]]; then
            prompt_secret "SSH password for $SSH_USER"; SSH_PASSWORD="$REPLY"
        fi
        if $need_windows; then
            prompt_secret "Windows Administrator password"; WIN_ADMIN_PASS="$REPLY"
        fi

        INVENTORY_INITIALIZED=""
        for mode in "${DEPLOY_MODES[@]}"; do
            DEPLOY_MODE="$mode"
            step "Reading Terraform state for workspace: $DEPLOY_MODE"
            pushd "$TF_DIR" > /dev/null
            terraform workspace select "$DEPLOY_MODE" 2>/dev/null || {
                warn "Terraform workspace '$DEPLOY_MODE' not found. Skipping."
                popd > /dev/null
                continue
            }
            if [[ "$DEPLOY_MODE" == *"3tier"* ]]; then
                if [[ "$DEPLOY_JAVA" == "true" ]]; then
                    JAVA_FE_IP="$(terraform output -json java_3tier_ips 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['frontend'])" 2>/dev/null || echo "")"
                    JAVA_APP_IP="$(terraform output -json java_3tier_ips 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['appserver'])" 2>/dev/null || echo "")"
                    JAVA_DB_IP="$(terraform output -json java_3tier_ips 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['database'])" 2>/dev/null || echo "")"
                fi
                if [[ "$DEPLOY_DOTNET" == "true" ]]; then
                    DOTNET_FE_IP="$(terraform output -json dotnet_3tier_ips 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['frontend'])" 2>/dev/null || echo "")"
                    DOTNET_APP_IP="$(terraform output -json dotnet_3tier_ips 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['appserver'])" 2>/dev/null || echo "")"
                    DOTNET_DB_IP="$(terraform output -json dotnet_3tier_ips 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['database'])" 2>/dev/null || echo "")"
                fi
                if [[ "$DEPLOY_PHP" == "true" ]]; then
                    PHP_FE_IP="$(terraform output -json php_3tier_ips 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['frontend'])" 2>/dev/null || echo "")"
                    PHP_APP_IP="$(terraform output -json php_3tier_ips 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['appserver'])" 2>/dev/null || echo "")"
                    PHP_DB_IP="$(terraform output -json php_3tier_ips 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['database'])" 2>/dev/null || echo "")"
                fi
            else
                [[ "$DEPLOY_JAVA" == "true" ]]   && JAVA_IP="$(terraform output -raw java_vm_ip 2>/dev/null || echo "")"
                [[ "$DEPLOY_DOTNET" == "true" ]] && DOTNET_IP="$(terraform output -raw dotnet_vm_ip 2>/dev/null || echo "")"
                [[ "$DEPLOY_PHP" == "true" ]]    && PHP_IP="$(terraform output -raw php_vm_ip 2>/dev/null || echo "")"
            fi
            popd > /dev/null
            write_inventory
        done

        step "Inventory rebuilt from Terraform state"
        run_domain_join
        exit 0
    fi

    # Handle --azmigrate-db flag for creating Azure Migrate DB users
    if [[ "${1:-}" == "--azmigrate-db" || "${1:-}" == "azmigrate-db" ]]; then
        echo ""
        echo -e "  ${C}================================================================${NC}"
        echo -e "  ${C}     Azure Migrate — Create DB Discovery Users${NC}"
        echo -e "  ${C}================================================================${NC}"
        echo ""
        check_prerequisites
        load_previous
        VM_DOMAIN="${PREV_VM_DOMAIN:-lab.local}"
        VM_DNS="${PREV_VM_DNS:-8.8.8.8}"

        DEPLOY_JAVA="${PREV_DEPLOY_JAVA:-true}"
        DEPLOY_DOTNET="${PREV_DEPLOY_DOTNET:-true}"
        DEPLOY_PHP="${PREV_DEPLOY_PHP:-true}"
        SSH_USER="${PREV_SSH_USER:-ubuntu}"
        SSH_AUTH_METHOD="${PREV_SSH_AUTH_METHOD:-password}"
        SSH_KEY="${PREV_SSH_KEY:-}"

        pushd "$TF_DIR" > /dev/null
        terraform init -input=false > /dev/null 2>&1
        local all_workspaces
        all_workspaces=$(terraform workspace list 2>/dev/null | sed 's/[* ]//g' | grep -v '^default$' | grep -v '^$' || echo "")
        popd > /dev/null

        if [[ -z "$all_workspaces" ]]; then
            err "No Terraform workspaces found. Deploy VMs first."
            exit 1
        fi

        DEPLOY_MODES=()
        while IFS= read -r ws; do
            DEPLOY_MODES+=("$ws")
        done <<< "$all_workspaces"
        step "Found Terraform workspaces: ${DEPLOY_MODES[*]}"

        local need_linux=false need_windows=false
        for m in "${DEPLOY_MODES[@]}"; do
            [[ "$m" == linux* ]] && need_linux=true
            [[ "$m" == windows* ]] && need_windows=true
        done
        if $need_linux && [[ "$SSH_AUTH_METHOD" == "password" ]]; then
            prompt_secret "SSH password for $SSH_USER"; SSH_PASSWORD="$REPLY"
        fi
        if $need_windows; then
            prompt_secret "Windows Administrator password"; WIN_ADMIN_PASS="$REPLY"
        fi

        INVENTORY_INITIALIZED=""
        for mode in "${DEPLOY_MODES[@]}"; do
            DEPLOY_MODE="$mode"
            step "Reading Terraform state for workspace: $DEPLOY_MODE"
            pushd "$TF_DIR" > /dev/null
            terraform workspace select "$DEPLOY_MODE" 2>/dev/null || {
                warn "Terraform workspace '$DEPLOY_MODE' not found. Skipping."
                popd > /dev/null
                continue
            }
            if [[ "$DEPLOY_MODE" == *"3tier"* ]]; then
                if [[ "$DEPLOY_JAVA" == "true" ]]; then
                    JAVA_FE_IP="$(terraform output -json java_3tier_ips 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['frontend'])" 2>/dev/null || echo "")"
                    JAVA_APP_IP="$(terraform output -json java_3tier_ips 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['appserver'])" 2>/dev/null || echo "")"
                    JAVA_DB_IP="$(terraform output -json java_3tier_ips 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['database'])" 2>/dev/null || echo "")"
                fi
                if [[ "$DEPLOY_DOTNET" == "true" ]]; then
                    DOTNET_FE_IP="$(terraform output -json dotnet_3tier_ips 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['frontend'])" 2>/dev/null || echo "")"
                    DOTNET_APP_IP="$(terraform output -json dotnet_3tier_ips 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['appserver'])" 2>/dev/null || echo "")"
                    DOTNET_DB_IP="$(terraform output -json dotnet_3tier_ips 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['database'])" 2>/dev/null || echo "")"
                fi
                if [[ "$DEPLOY_PHP" == "true" ]]; then
                    PHP_FE_IP="$(terraform output -json php_3tier_ips 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['frontend'])" 2>/dev/null || echo "")"
                    PHP_APP_IP="$(terraform output -json php_3tier_ips 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['appserver'])" 2>/dev/null || echo "")"
                    PHP_DB_IP="$(terraform output -json php_3tier_ips 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['database'])" 2>/dev/null || echo "")"
                fi
            else
                [[ "$DEPLOY_JAVA" == "true" ]]   && JAVA_IP="$(terraform output -raw java_vm_ip 2>/dev/null || echo "")"
                [[ "$DEPLOY_DOTNET" == "true" ]] && DOTNET_IP="$(terraform output -raw dotnet_vm_ip 2>/dev/null || echo "")"
                [[ "$DEPLOY_PHP" == "true" ]]    && PHP_IP="$(terraform output -raw php_vm_ip 2>/dev/null || echo "")"
            fi
            popd > /dev/null
            write_inventory
        done

        step "Inventory rebuilt from Terraform state"
        run_azmigrate_db
        exit 0
    fi

    # Handle --reinventory flag: rebuild inventory from Terraform state, no deploy
    if [[ "${1:-}" == "--reinventory" || "${1:-}" == "reinventory" ]]; then
        echo ""
        echo -e "  ${C}================================================================${NC}"
        echo -e "  ${C}     Reinventory — Rebuild hosts.ini from Terraform State${NC}"
        echo -e "  ${C}================================================================${NC}"
        echo ""
        check_prerequisites
        load_previous

        DEPLOY_JAVA="${PREV_DEPLOY_JAVA:-true}"
        DEPLOY_DOTNET="${PREV_DEPLOY_DOTNET:-true}"
        DEPLOY_PHP="${PREV_DEPLOY_PHP:-true}"
        SSH_USER="${PREV_SSH_USER:-ubuntu}"
        SSH_AUTH_METHOD="${PREV_SSH_AUTH_METHOD:-password}"
        SSH_KEY="${PREV_SSH_KEY:-}"
        OS_CHOICE="${PREV_OS_CHOICE:-linux}"
        VM_DOMAIN="${PREV_VM_DOMAIN:-lab.local}"
        VM_DNS="${PREV_VM_DNS:-8.8.8.8}"

        pushd "$TF_DIR" > /dev/null
        terraform init -input=false > /dev/null 2>&1
        local all_workspaces
        all_workspaces=$(terraform workspace list 2>/dev/null | sed 's/[* ]//g' | grep -v '^default$' | grep -v '^$' || echo "")
        popd > /dev/null

        if [[ -z "$all_workspaces" ]]; then
            err "No Terraform workspaces found. Deploy VMs first."
            exit 1
        fi

        DEPLOY_MODES=()
        while IFS= read -r ws; do
            DEPLOY_MODES+=("$ws")
        done <<< "$all_workspaces"
        step "Found Terraform workspaces: ${DEPLOY_MODES[*]}"

        local need_linux=false need_windows=false
        for m in "${DEPLOY_MODES[@]}"; do
            [[ "$m" == linux* ]] && need_linux=true
            [[ "$m" == windows* ]] && need_windows=true
        done
        if $need_linux && [[ "$SSH_AUTH_METHOD" == "password" ]]; then
            prompt_secret "SSH password for $SSH_USER"; SSH_PASSWORD="$REPLY"
        fi
        if $need_windows; then
            prompt_secret "Windows Administrator password"; WIN_ADMIN_PASS="$REPLY"
        fi

        INVENTORY_INITIALIZED=""
        for mode in "${DEPLOY_MODES[@]}"; do
            DEPLOY_MODE="$mode"
            step "Reading Terraform state for workspace: $DEPLOY_MODE"
            pushd "$TF_DIR" > /dev/null
            terraform workspace select "$DEPLOY_MODE" 2>/dev/null || {
                warn "Terraform workspace '$DEPLOY_MODE' not found. Skipping."
                popd > /dev/null
                continue
            }
            if [[ "$DEPLOY_MODE" == *"3tier"* ]]; then
                if [[ "$DEPLOY_JAVA" == "true" ]]; then
                    JAVA_FE_IP="$(terraform output -json java_3tier_ips 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['frontend'])" 2>/dev/null || echo "")"
                    JAVA_APP_IP="$(terraform output -json java_3tier_ips 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['appserver'])" 2>/dev/null || echo "")"
                    JAVA_DB_IP="$(terraform output -json java_3tier_ips 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['database'])" 2>/dev/null || echo "")"
                fi
                if [[ "$DEPLOY_DOTNET" == "true" ]]; then
                    DOTNET_FE_IP="$(terraform output -json dotnet_3tier_ips 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['frontend'])" 2>/dev/null || echo "")"
                    DOTNET_APP_IP="$(terraform output -json dotnet_3tier_ips 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['appserver'])" 2>/dev/null || echo "")"
                    DOTNET_DB_IP="$(terraform output -json dotnet_3tier_ips 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['database'])" 2>/dev/null || echo "")"
                fi
                if [[ "$DEPLOY_PHP" == "true" ]]; then
                    PHP_FE_IP="$(terraform output -json php_3tier_ips 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['frontend'])" 2>/dev/null || echo "")"
                    PHP_APP_IP="$(terraform output -json php_3tier_ips 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['appserver'])" 2>/dev/null || echo "")"
                    PHP_DB_IP="$(terraform output -json php_3tier_ips 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['database'])" 2>/dev/null || echo "")"
                fi
            else
                [[ "$DEPLOY_JAVA" == "true" ]]   && JAVA_IP="$(terraform output -raw java_vm_ip 2>/dev/null || echo "")"
                [[ "$DEPLOY_DOTNET" == "true" ]] && DOTNET_IP="$(terraform output -raw dotnet_vm_ip 2>/dev/null || echo "")"
                [[ "$DEPLOY_PHP" == "true" ]]    && PHP_IP="$(terraform output -raw php_vm_ip 2>/dev/null || echo "")"
            fi
            popd > /dev/null
            write_inventory
        done

        step "Inventory rebuilt: $ANSIBLE_DIR/inventory/hosts.ini"
        echo -e "  ${G}Done. You can now run ansible manually or use --resume.${NC}"
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
        load_previous

        # Restore app deployment flags
        DEPLOY_JAVA="${PREV_DEPLOY_JAVA:-true}"
        DEPLOY_DOTNET="${PREV_DEPLOY_DOTNET:-true}"
        DEPLOY_PHP="${PREV_DEPLOY_PHP:-true}"

        # Derive DEPLOY_MODES from saved wizard choices
        DEPLOY_MODES=()
        local r_os="${PREV_OS_CHOICE:-linux}"
        local r_arch="${PREV_ARCH_CHOICE:-single}"
        if [[ "$r_os" == "linux" || "$r_os" == "both" ]]; then
            [[ "$r_arch" == "3tier" ]] && DEPLOY_MODES+=("linux-3tier") || DEPLOY_MODES+=("linux")
        fi
        if [[ "$r_os" == "windows" || "$r_os" == "both" ]]; then
            [[ "$r_arch" == "3tier" ]] && DEPLOY_MODES+=("windows-3tier") || DEPLOY_MODES+=("windows")
        fi

        echo -e "  ${C}Resuming: app=${PREV_APP_SELECTION:-all} os=$r_os arch=$r_arch${NC}"
        echo -e "  ${C}Modes: ${DEPLOY_MODES[*]}${NC}"
        echo ""

        VSPHERE_SERVER="${PREV_VSPHERE_SERVER:-}"
        SSH_USER="${PREV_SSH_USER:-ubuntu}"
        SSH_AUTH_METHOD="${PREV_SSH_AUTH_METHOD:-password}"
        SSH_KEY="${PREV_SSH_KEY:-}"

        # Restore all config variables from saved tfvars so write_tfvars()
        # can regenerate a complete file without prompting the user.
        APP_SELECTION="${PREV_APP_SELECTION:-all}"
        OS_CHOICE="$r_os"
        ARCH_CHOICE="$r_arch"
        VSPHERE_USER="${PREV_VSPHERE_USER:-administrator@vsphere.local}"
        VSPHERE_PASSWORD=""
        VSPHERE_SSL="${PREV_VSPHERE_SSL:-true}"
        VSPHERE_DC="${PREV_VSPHERE_DC:-Datacenter1}"
        VSPHERE_CLUSTER="${PREV_VSPHERE_CLUSTER:-Cluster1}"
        VSPHERE_DS="${PREV_VSPHERE_DS:-datastore1}"
        VSPHERE_NET="${PREV_VSPHERE_NET:-VM Network}"
        VSPHERE_FOLDER="${PREV_VSPHERE_FOLDER:-}"
        VM_TEMPLATE="${PREV_VM_TEMPLATE:-ubuntu-2204-template}"
        VM_GW="${PREV_VM_GW:-192.168.1.1}"
        VM_MASK="${PREV_VM_MASK:-24}"
        VM_DOMAIN="${PREV_VM_DOMAIN:-lab.local}"
        VM_DNS="${PREV_VM_DNS:-8.8.8.8,8.8.4.4}"
        WIN_TEMPLATE="${PREV_WIN_TEMPLATE:-windows-2019-template}"
        # Single-VM variables
        JAVA_IP="${PREV_JAVA_IP:-}"; JAVA_HOSTNAME="${PREV_JAVA_HOSTNAME:-legacy-java-vm}"
        JAVA_CPU="${PREV_JAVA_CPU:-2}"; JAVA_MEM="${PREV_JAVA_MEM:-4096}"; JAVA_DISK="${PREV_JAVA_DISK:-40}"
        DOTNET_IP="${PREV_DOTNET_IP:-}"; DOTNET_HOSTNAME="${PREV_DOTNET_HOSTNAME:-legacy-dotnet-vm}"
        DOTNET_CPU="${PREV_DOTNET_CPU:-2}"; DOTNET_MEM="${PREV_DOTNET_MEM:-4096}"; DOTNET_DISK="${PREV_DOTNET_DISK:-40}"
        PHP_IP="${PREV_PHP_IP:-}"; PHP_HOSTNAME="${PREV_PHP_HOSTNAME:-legacy-php-vm}"
        PHP_CPU="${PREV_PHP_CPU:-2}"; PHP_MEM="${PREV_PHP_MEM:-2048}"; PHP_DISK="${PREV_PHP_DISK:-30}"
        # 3-Tier hostnames
        JAVA_FE_HOSTNAME="${PREV_JAVA_FE_HOSTNAME:-lin-java-fe}"
        JAVA_APP_HOSTNAME="${PREV_JAVA_APP_HOSTNAME:-lin-java-app}"
        JAVA_DB_HOSTNAME="${PREV_JAVA_DB_HOSTNAME:-lin-java-db}"
        DOTNET_FE_HOSTNAME="${PREV_DOTNET_FE_HOSTNAME:-lin-dotnet-fe}"
        DOTNET_APP_HOSTNAME="${PREV_DOTNET_APP_HOSTNAME:-lin-dotnet-app}"
        DOTNET_DB_HOSTNAME="${PREV_DOTNET_DB_HOSTNAME:-lin-dotnet-db}"
        PHP_FE_HOSTNAME="${PREV_PHP_FE_HOSTNAME:-lin-php-fe}"
        PHP_APP_HOSTNAME="${PREV_PHP_APP_HOSTNAME:-lin-php-app}"
        PHP_DB_HOSTNAME="${PREV_PHP_DB_HOSTNAME:-lin-php-db}"
        WIN_JAVA_FE_HOSTNAME="${PREV_WIN_JAVA_FE_HOSTNAME:-win-java-fe}"
        WIN_JAVA_APP_HOSTNAME="${PREV_WIN_JAVA_APP_HOSTNAME:-win-java-app}"
        WIN_JAVA_DB_HOSTNAME="${PREV_WIN_JAVA_DB_HOSTNAME:-win-java-db}"
        WIN_DOTNET_FE_HOSTNAME="${PREV_WIN_DOTNET_FE_HOSTNAME:-win-dotnet-fe}"
        WIN_DOTNET_APP_HOSTNAME="${PREV_WIN_DOTNET_APP_HOSTNAME:-win-dotnet-app}"
        WIN_DOTNET_DB_HOSTNAME="${PREV_WIN_DOTNET_DB_HOSTNAME:-win-dotnet-db}"
        WIN_PHP_FE_HOSTNAME="${PREV_WIN_PHP_FE_HOSTNAME:-win-php-fe}"
        WIN_PHP_APP_HOSTNAME="${PREV_WIN_PHP_APP_HOSTNAME:-win-php-app}"
        WIN_PHP_DB_HOSTNAME="${PREV_WIN_PHP_DB_HOSTNAME:-win-php-db}"
        # 3-Tier IPs (fallback — overridden from terraform state below)
        JAVA_FE_IP="${PREV_JAVA_FE_IP:-}"; JAVA_APP_IP="${PREV_JAVA_APP_IP:-}"; JAVA_DB_IP="${PREV_JAVA_DB_IP:-}"
        DOTNET_FE_IP="${PREV_DOTNET_FE_IP:-}"; DOTNET_APP_IP="${PREV_DOTNET_APP_IP:-}"; DOTNET_DB_IP="${PREV_DOTNET_DB_IP:-}"
        PHP_FE_IP="${PREV_PHP_FE_IP:-}"; PHP_APP_IP="${PREV_PHP_APP_IP:-}"; PHP_DB_IP="${PREV_PHP_DB_IP:-}"
        WIN_JAVA_FE_IP="${PREV_WIN_JAVA_FE_IP:-}"; WIN_JAVA_APP_IP="${PREV_WIN_JAVA_APP_IP:-}"; WIN_JAVA_DB_IP="${PREV_WIN_JAVA_DB_IP:-}"
        WIN_DOTNET_FE_IP="${PREV_WIN_DOTNET_FE_IP:-}"; WIN_DOTNET_APP_IP="${PREV_WIN_DOTNET_APP_IP:-}"; WIN_DOTNET_DB_IP="${PREV_WIN_DOTNET_DB_IP:-}"
        WIN_PHP_FE_IP="${PREV_WIN_PHP_FE_IP:-}"; WIN_PHP_APP_IP="${PREV_WIN_PHP_APP_IP:-}"; WIN_PHP_DB_IP="${PREV_WIN_PHP_DB_IP:-}"
        # 3-Tier VM sizing
        FE_CPU="${PREV_FE_CPU:-1}"; FE_MEM="${PREV_FE_MEM:-2048}"; FE_DISK="${PREV_FE_DISK:-20}"
        APP_CPU="${PREV_APP_CPU:-2}"; APP_MEM="${PREV_APP_MEM:-4096}"; APP_DISK="${PREV_APP_DISK:-40}"
        DB_CPU="${PREV_DB_CPU:-2}"; DB_MEM="${PREV_DB_MEM:-4096}"; DB_DISK="${PREV_DB_DISK:-60}"
        # App config
        PETCLINIC_REPO="${PREV_PETCLINIC_REPO:-}"; PETCLINIC_BRANCH="${PREV_PETCLINIC_BRANCH:-main}"
        JAVA_VER="${PREV_JAVA_VER:-17}"
        DOTNET_SDK="${PREV_DOTNET_SDK:-6.0}"; DOTNET_REPO="${PREV_DOTNET_REPO:-}"; DOTNET_BRANCH="${PREV_DOTNET_BRANCH:-main}"
        PHP_VER="${PREV_PHP_VER:-8.1}"; PHP_REPO="${PREV_PHP_REPO:-}"; PHP_BRANCH="${PREV_PHP_BRANCH:-10.x}"
        AZ_AGENT="${PREV_AZ_AGENT:-false}"

        # Prompt for credentials (passwords are never saved)
        local need_linux=false need_windows=false
        for m in "${DEPLOY_MODES[@]}"; do
            [[ "$m" == linux* ]] && need_linux=true
            [[ "$m" == windows* ]] && need_windows=true
        done
        if $need_linux && [[ "$SSH_AUTH_METHOD" == "password" ]]; then
            prompt_secret "SSH password for $SSH_USER"; SSH_PASSWORD="$REPLY"
        fi
        if $need_windows; then
            prompt_secret "Windows Administrator password"; WIN_ADMIN_PASS="$REPLY"
        fi

        # Resume each mode
        INVENTORY_INITIALIZED=""
        for mode in "${DEPLOY_MODES[@]}"; do
            DEPLOY_MODE="$mode"
            echo ""
            header "Resuming mode: $DEPLOY_MODE"

            # Get IPs from Terraform state
            pushd "$TF_DIR" > /dev/null
            terraform init -input=false > /dev/null 2>&1
            terraform workspace select "$DEPLOY_MODE" 2>/dev/null || {
                warn "Terraform workspace '$DEPLOY_MODE' not found. Skipping."
                popd > /dev/null
                continue
            }
            if [[ "$DEPLOY_MODE" == *"3tier"* ]]; then
                if [[ "$DEPLOY_JAVA" == "true" ]]; then
                    JAVA_FE_IP="$(terraform output -json java_3tier_ips 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['frontend'])" 2>/dev/null || echo "")"
                    JAVA_APP_IP="$(terraform output -json java_3tier_ips 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['appserver'])" 2>/dev/null || echo "")"
                    JAVA_DB_IP="$(terraform output -json java_3tier_ips 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['database'])" 2>/dev/null || echo "")"
                fi
                if [[ "$DEPLOY_DOTNET" == "true" ]]; then
                    DOTNET_FE_IP="$(terraform output -json dotnet_3tier_ips 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['frontend'])" 2>/dev/null || echo "")"
                    DOTNET_APP_IP="$(terraform output -json dotnet_3tier_ips 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['appserver'])" 2>/dev/null || echo "")"
                    DOTNET_DB_IP="$(terraform output -json dotnet_3tier_ips 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['database'])" 2>/dev/null || echo "")"
                fi
                if [[ "$DEPLOY_PHP" == "true" ]]; then
                    PHP_FE_IP="$(terraform output -json php_3tier_ips 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['frontend'])" 2>/dev/null || echo "")"
                    PHP_APP_IP="$(terraform output -json php_3tier_ips 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['appserver'])" 2>/dev/null || echo "")"
                    PHP_DB_IP="$(terraform output -json php_3tier_ips 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['database'])" 2>/dev/null || echo "")"
                fi
                step "Using 3-tier IPs from Terraform state"
            else
                [[ "$DEPLOY_JAVA" == "true" ]]   && JAVA_IP="$(terraform output -raw java_vm_ip 2>/dev/null || echo "$PREV_JAVA_IP")"
                [[ "$DEPLOY_DOTNET" == "true" ]] && DOTNET_IP="$(terraform output -raw dotnet_vm_ip 2>/dev/null || echo "$PREV_DOTNET_IP")"
                [[ "$DEPLOY_PHP" == "true" ]]    && PHP_IP="$(terraform output -raw php_vm_ip 2>/dev/null || echo "$PREV_PHP_IP")"
                step "Using IPs from Terraform state"
            fi
            popd > /dev/null

            # Regenerate inventory and run ansible
            write_tfvars
            write_inventory
            run_ansible_resume
            run_verify
        done
        exit 0
    fi

    # Handle --quick flag: reuse saved config, only prompt for passwords
    if [[ "${1:-}" == "--quick" || "${1:-}" == "quick" ]]; then
        echo ""
        echo -e "  ${C}================================================================${NC}"
        echo -e "  ${C}     Quick Mode — Reuse Previous Config${NC}"
        echo -e "  ${C}     Only prompting for passwords (not saved)${NC}"
        echo -e "  ${C}================================================================${NC}"
        echo ""
        check_prerequisites
        load_previous

        if [[ ! -f "$TFVARS_FILE" ]]; then
            err "No previous config found (terraform.tfvars). Run without --quick first."
            exit 1
        fi

        QUICK_MODE=true

        # Restore selections from saved config
        APP_SELECTION="$PREV_APP_SELECTION"
        OS_CHOICE="$PREV_OS_CHOICE"
        ARCH_CHOICE="$PREV_ARCH_CHOICE"
        # Derive deploy flags from the wizard app selection (not merged tfvars flags)
        case "$APP_SELECTION" in
            java)   DEPLOY_JAVA=true;  DEPLOY_DOTNET=false; DEPLOY_PHP=false ;;
            dotnet) DEPLOY_JAVA=false; DEPLOY_DOTNET=true;  DEPLOY_PHP=false ;;
            php)    DEPLOY_JAVA=false; DEPLOY_DOTNET=false; DEPLOY_PHP=true  ;;
            *)      DEPLOY_JAVA=true;  DEPLOY_DOTNET=true;  DEPLOY_PHP=true  ;;
        esac

        # Derive deploy modes
        DEPLOY_MODES=()
        if [[ "$OS_CHOICE" == "linux" || "$OS_CHOICE" == "both" ]]; then
            [[ "$ARCH_CHOICE" == "3tier" ]] && DEPLOY_MODES+=("linux-3tier") || DEPLOY_MODES+=("linux")
        fi
        if [[ "$OS_CHOICE" == "windows" || "$OS_CHOICE" == "both" ]]; then
            [[ "$ARCH_CHOICE" == "3tier" ]] && DEPLOY_MODES+=("windows-3tier") || DEPLOY_MODES+=("windows")
        fi
        DEPLOY_MODE="${DEPLOY_MODES[0]}"

        step "Loaded: App=${APP_SELECTION}  OS=${OS_CHOICE}  Arch=${ARCH_CHOICE}"
        step "Modes: ${DEPLOY_MODES[*]}"
        echo ""

        collect_vcenter
        collect_infra
        collect_network
        collect_vms
        collect_apps
        collect_migrate

        show_summary

        echo ""
        prompt_yn "Proceed with these settings?" "y" || { warn "Aborted."; exit 0; }

        header "Saving Configuration Files"
        write_tfvars
        write_ansible_vars
        write_inventory

        echo ""
        echo -e "  ${G}Files saved. Ready to deploy.${NC}"
        echo ""
        echo -e "  ${Y}What would you like to do next?${NC}"
        echo -e "    ${G}1)${NC} Run full pipeline (Terraform + Ansible + Verify)"
        echo -e "    ${G}2)${NC} Ansible only — skip Terraform, re-run playbooks on existing VMs"
        echo -e "    ${G}3)${NC} Stop here — I'll run Terraform & Ansible myself later"
        echo -e "    ${G}4)${NC} DNS Registration only (create A records — no domain join)"
        echo -e "    ${G}5)${NC} Domain Join (join AD domain — DNS registration is automatic)"
        echo -e "    ${G}6)${NC} Azure Migrate DB Users (create discovery accounts on PostgreSQL/MySQL)"
        read -rp "  Choice [3]: " qchoice
        qchoice="${qchoice:-3}"
        if [[ "$qchoice" == "1" ]]; then
            INVENTORY_INITIALIZED=""
            for mode in "${DEPLOY_MODES[@]}"; do
                DEPLOY_MODE="$mode"
                write_tfvars; write_inventory
                run_terraform; run_ansible; run_verify
            done
            echo ""
            echo -e "  ${Y}Post-deploy: DNS / Domain Join${NC}"
            echo -e "    ${G}1)${NC} DNS Registration only (A records — no domain join)"
            echo -e "    ${G}2)${NC} Domain Join (join AD domain — DNS registration is automatic)"
            echo -e "    ${G}3)${NC} Skip"
            read -rp "  Choice [3]: " post_choice
            post_choice="${post_choice:-3}"
            [[ "$post_choice" == "1" ]] && run_dns_register
            [[ "$post_choice" == "2" ]] && run_domain_join
        elif [[ "$qchoice" == "2" ]]; then
            INVENTORY_INITIALIZED=""
            for mode in "${DEPLOY_MODES[@]}"; do
                DEPLOY_MODE="$mode"
                write_tfvars; write_inventory
                run_ansible; run_verify
            done
            echo ""
            echo -e "  ${Y}Post-deploy: DNS / Domain Join${NC}"
            echo -e "    ${G}1)${NC} DNS Registration only (A records — no domain join)"
            echo -e "    ${G}2)${NC} Domain Join (join AD domain — DNS registration is automatic)"
            echo -e "    ${G}3)${NC} Skip"
            read -rp "  Choice [3]: " post_choice
            post_choice="${post_choice:-3}"
            [[ "$post_choice" == "1" ]] && run_dns_register
            [[ "$post_choice" == "2" ]] && run_domain_join
        elif [[ "$qchoice" == "4" ]]; then
            run_dns_register
        elif [[ "$qchoice" == "5" ]]; then
            run_domain_join
        elif [[ "$qchoice" == "6" ]]; then
            run_azmigrate_db
        else
            step "Config saved. Run manually when ready."
        fi
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

    # --- Step 1: Application Selection ---
    header "Application Selection"
    echo -e "  ${Y}Which application(s) do you want to deploy?${NC}"
    echo -e "    ${G}1)${NC} Java     — Spring PetClinic + PostgreSQL"
    echo -e "    ${G}2)${NC} .NET     — ASP.NET + SQL Server"
    echo -e "    ${G}3)${NC} PHP      — Laravel + MySQL"
    echo -e "    ${G}4)${NC} All      — Java + .NET + PHP (all three)"
    local default_app_num
    case "$PREV_APP_SELECTION" in
        java) default_app_num="1" ;;
        dotnet) default_app_num="2" ;;
        php) default_app_num="3" ;;
        *) default_app_num="4" ;;
    esac
    read -rp "  Choice [1/2/3/4] (default: $default_app_num): " APP_CHOICE
    APP_CHOICE="${APP_CHOICE:-$default_app_num}"
    case "$APP_CHOICE" in
        1) APP_SELECTION="java";   DEPLOY_JAVA=true;  DEPLOY_DOTNET=false; DEPLOY_PHP=false
           step "App: Java (PetClinic + PostgreSQL)" ;;
        2) APP_SELECTION="dotnet"; DEPLOY_JAVA=false; DEPLOY_DOTNET=true;  DEPLOY_PHP=false
           step "App: .NET (ASP.NET + SQL Server)" ;;
        3) APP_SELECTION="php";    DEPLOY_JAVA=false; DEPLOY_DOTNET=false; DEPLOY_PHP=true
           step "App: PHP (Laravel + MySQL)" ;;
        *) APP_SELECTION="all";    DEPLOY_JAVA=true;  DEPLOY_DOTNET=true;  DEPLOY_PHP=true
           step "App: All (Java + .NET + PHP)" ;;
    esac

    # --- Step 2: Operating System ---
    echo ""
    echo -e "  ${Y}Which operating system?${NC}"
    echo -e "    ${G}1)${NC} Linux    — Ubuntu 22.04 VMs"
    echo -e "    ${G}2)${NC} Windows  — Windows Server 2019 VMs"
    echo -e "    ${G}3)${NC} Both     — Deploy on Linux AND Windows"
    local default_os_num
    case "$PREV_OS_CHOICE" in
        windows) default_os_num="2" ;;
        both) default_os_num="3" ;;
        *) default_os_num="1" ;;
    esac
    read -rp "  Choice [1/2/3] (default: $default_os_num): " OS_NUM
    OS_NUM="${OS_NUM:-$default_os_num}"
    case "$OS_NUM" in
        2) OS_CHOICE="windows"; step "OS: Windows Server 2019" ;;
        3) OS_CHOICE="both";    step "OS: Both (Linux + Windows)" ;;
        *) OS_CHOICE="linux";   step "OS: Linux (Ubuntu 22.04)" ;;
    esac

    # --- Step 3: Architecture ---
    echo ""
    echo -e "  ${Y}Which architecture?${NC}"
    echo -e "    ${G}1)${NC} Single-VM  — All-in-one: app + database on same VM"
    echo -e "    ${G}2)${NC} 3-Tier     — Separate Frontend, App Server, and Database VMs"
    local default_arch_num
    case "$PREV_ARCH_CHOICE" in
        3tier) default_arch_num="2" ;;
        *) default_arch_num="1" ;;
    esac
    read -rp "  Choice [1/2] (default: $default_arch_num): " ARCH_NUM
    ARCH_NUM="${ARCH_NUM:-$default_arch_num}"
    case "$ARCH_NUM" in
        2) ARCH_CHOICE="3tier";  step "Architecture: 3-Tier (Frontend + App + DB)" ;;
        *) ARCH_CHOICE="single"; step "Architecture: Single-VM (all-in-one)" ;;
    esac

    # --- Derive deploy modes from selections ---
    DEPLOY_MODES=()
    if [[ "$OS_CHOICE" == "linux" || "$OS_CHOICE" == "both" ]]; then
        if [[ "$ARCH_CHOICE" == "3tier" ]]; then
            DEPLOY_MODES+=("linux-3tier")
        else
            DEPLOY_MODES+=("linux")
        fi
    fi
    if [[ "$OS_CHOICE" == "windows" || "$OS_CHOICE" == "both" ]]; then
        if [[ "$ARCH_CHOICE" == "3tier" ]]; then
            DEPLOY_MODES+=("windows-3tier")
        else
            DEPLOY_MODES+=("windows")
        fi
    fi
    # Set DEPLOY_MODE to the first mode for collection functions
    DEPLOY_MODE="${DEPLOY_MODES[0]}"

    local vm_count=0
    local apps_count=0
    [[ "$DEPLOY_JAVA" == "true" ]]   && ((apps_count+=1)) || true
    [[ "$DEPLOY_DOTNET" == "true" ]] && ((apps_count+=1)) || true
    [[ "$DEPLOY_PHP" == "true" ]]    && ((apps_count+=1)) || true
    if [[ "$ARCH_CHOICE" == "3tier" ]]; then
        vm_count=$((apps_count * 3))
    else
        vm_count=$apps_count
    fi
    if [[ "$OS_CHOICE" == "both" ]]; then
        vm_count=$((vm_count * 2))
    fi
    echo ""
    step "Total VMs to deploy: $vm_count"
    echo ""

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
    echo -e "    ${G}7)${NC} DNS Registration only (create A records — no domain join)"
    echo -e "    ${G}8)${NC} Domain Join (join AD domain — DNS registration is automatic)"
    echo -e "    ${G}9)${NC} Azure Migrate DB Users (create discovery accounts on PostgreSQL/MySQL)"
    read -rp "  Choice [2]: " choice
    choice="${choice:-2}"

    case "$choice" in
        1) INVENTORY_INITIALIZED=""
           for mode in "${DEPLOY_MODES[@]}"; do
               DEPLOY_MODE="$mode"
               write_tfvars; write_inventory
               run_terraform; run_ansible; run_verify
           done
           echo ""
           echo -e "  ${Y}Post-deploy: DNS / Domain Join${NC}"
           echo -e "    ${G}1)${NC} DNS Registration only (A records — no domain join)"
           echo -e "    ${G}2)${NC} Domain Join (join AD domain — DNS registration is automatic)"
           echo -e "    ${G}3)${NC} Skip"
           read -rp "  Choice [3]: " post_choice
           post_choice="${post_choice:-3}"
           [[ "$post_choice" == "1" ]] && run_dns_register
           [[ "$post_choice" == "2" ]] && run_domain_join ;;
        2) step "Config files saved. Run manually when ready:"
           for mode in "${DEPLOY_MODES[@]}"; do
               echo -e "    ${GR}cd terraform && terraform init && terraform workspace select -or-create $mode && terraform apply${NC}"
           done
           echo -e "    ${GR}cd ansible && ansible-playbook -i inventory/hosts.ini site.yml${NC}"
           [[ "$ARCH" == "3tier" ]] && echo -e "    ${GR}(3-tier: use playbooks/3tier/site-3tier.yml or site-3tier-win.yml)${NC}" ;;
        3) INVENTORY_INITIALIZED=""
           for mode in "${DEPLOY_MODES[@]}"; do
               DEPLOY_MODE="$mode"
               write_tfvars; write_inventory
               run_terraform
           done ;;
        4) INVENTORY_INITIALIZED=""
           for mode in "${DEPLOY_MODES[@]}"; do
               DEPLOY_MODE="$mode"
               write_tfvars; write_inventory
               run_ansible; run_verify
           done
           echo ""
           echo -e "  ${Y}Post-deploy: DNS / Domain Join${NC}"
           echo -e "    ${G}1)${NC} DNS Registration only (A records — no domain join)"
           echo -e "    ${G}2)${NC} Domain Join (join AD domain — DNS registration is automatic)"
           echo -e "    ${G}3)${NC} Skip"
           read -rp "  Choice [3]: " post_choice
           post_choice="${post_choice:-3}"
           [[ "$post_choice" == "1" ]] && run_dns_register
           [[ "$post_choice" == "2" ]] && run_domain_join ;;
        5) INVENTORY_INITIALIZED=""
           for mode in "${DEPLOY_MODES[@]}"; do
               DEPLOY_MODE="$mode"
               write_tfvars; write_inventory
               run_ansible_resume; run_verify
           done ;;
        6) run_destroy ;;
        7) run_dns_register ;;
        8) run_domain_join ;;
        9) run_azmigrate_db ;;
        *) err "Invalid choice"; exit 1 ;;
    esac
}

main "$@"
