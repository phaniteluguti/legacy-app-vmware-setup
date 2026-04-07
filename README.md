# VMware Legacy App Lab — Azure Migrate Assessment Setup

Automated deployment of legacy applications (.NET, Java, PHP) on VMware Ubuntu VMs to simulate a real-world on-premises environment for **Azure Migrate discovery and assessment**.

This repo provisions 3 VMware VMs, installs a full web + database stack on each, and configures them for Azure Migrate agentless discovery — all from a single interactive wizard or script.

---

## Table of Contents

1. [What This Does](#what-this-does)
2. [Architecture](#architecture)
3. [Prerequisites](#prerequisites)
4. [Where to Start — Step by Step](#where-to-start--step-by-step)
   - [Step 1: Clone This Repo](#step-1-clone-this-repo)
   - [Step 2: Install Tools on Your Machine](#step-2-install-tools-on-your-machine)
   - [Step 3: Prepare a VM Template in vSphere](#step-3-prepare-a-vm-template-in-vsphere)
   - [Step 4: Run the Interactive Setup Wizard](#step-4-run-the-interactive-setup-wizard)
   - [Step 5: Verify Deployment](#step-5-verify-deployment)
5. [Manual Setup (Alternative to Wizard)](#manual-setup-alternative-to-wizard)
6. [What Gets Deployed](#what-gets-deployed)
7. [Directory Structure](#directory-structure)
8. [Configuration Reference](#configuration-reference)
9. [Azure Migrate — Next Steps](#azure-migrate--next-steps)
10. [Troubleshooting](#troubleshooting)
11. [Cleanup](#cleanup)

---

## What This Does

| Phase | Tool | Action |
|-------|------|--------|
| **Provision** | Terraform | Clones an Ubuntu 22.04 template in vSphere into 3 VMs with static IPs |
| **Deploy** | Ansible | Installs Java/PetClinic + PostgreSQL, .NET/MVC + SQL Server, PHP/Laravel + MySQL |
| **Prepare** | Ansible | Enables SSH, sysstat, firewall rules, and optional Azure Migrate Dependency Agent |
| **Assess** | Azure Migrate | You point the Azure Migrate appliance at your vCenter and discover all 3 VMs |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     VMware vSphere                          │
│                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │  VM: java-vm  │  │  VM: dotnet-vm│  │  VM: php-vm  │      │
│  │  Ubuntu 22.04 │  │  Ubuntu 22.04 │  │  Ubuntu 22.04│      │
│  │               │  │               │  │              │      │
│  │  Spring       │  │  ASP.NET Core │  │  Laravel     │      │
│  │  PetClinic    │  │  MVC + Nginx  │  │  + Apache2   │      │
│  │  (Java 17)    │  │  (.NET 6)     │  │  (PHP 8.1)   │      │
│  │               │  │               │  │              │      │
│  │  PostgreSQL   │  │  SQL Server   │  │  MySQL 8.0   │      │
│  │  15           │  │  2022 Express │  │              │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
│                                                             │
└─────────────────────────────────────────────────────────────┘
         │
         ▼  Azure Migrate Appliance discovers these VMs
┌─────────────────────────────────────────────────────────────┐
│  Migration Targets:                                         │
│  Azure IaaS (VMs)           │  Azure PaaS                   │
│  • Azure VMs                │  • App Service                 │
│  • Managed Disks            │  • Azure SQL / Postgres / MySQL│
│  • NSGs, VNets              │  • Azure Container Apps        │
└─────────────────────────────────────────────────────────────┘
```

---

## Prerequisites

### On Your Machine (the "control node")

| Tool | Version | How to Install | Why Needed |
|------|---------|----------------|------------|
| **Terraform** | >= 1.5 | [terraform.io/install](https://developer.hashicorp.com/terraform/install) | Creates VMs on vSphere |
| **Ansible** | >= 2.14 | `pip install ansible` or use WSL on Windows | Deploys apps over SSH |
| **SSH client** | any | Built into Windows 10+, macOS, Linux | Ansible connects to VMs |
| **Git** | any | [git-scm.com](https://git-scm.com/) | Clone this repo |

**Windows users:** Ansible doesn't run natively on Windows. Use one of:
- **WSL2** (recommended): `wsl --install`, then `pip install ansible` inside WSL
- **Docker**: Run Ansible from a container
- **Azure Cloud Shell**: Has Terraform + Ansible pre-installed

### In Your VMware Environment

| Requirement | Details |
|-------------|---------|
| **vCenter Server** | 6.7 or later — Terraform talks to the vCenter API |
| **vSphere credentials** | A user with permission to create VMs (e.g., `administrator@vsphere.local`) |
| **Ubuntu 22.04 VM template** | A template in your vCenter inventory (see [Step 3](#step-3-prepare-a-vm-template-in-vsphere)) |
| **Network** | A port group with DHCP or a static IP range you can assign to 3 VMs |
| **SSH key pair** | The public key must be in the template; you keep the private key on your machine |

### Information You'll Need to Gather

Before running the wizard, collect these from your vCenter:

```
vCenter server address        → e.g., vcenter.mycompany.com
vCenter username/password     → e.g., administrator@vsphere.local
Datacenter name               → visible in vCenter inventory tree
Cluster name                  → the compute cluster under the datacenter
Datastore name                → where VM disks will be stored
Network/Port Group name       → the network VMs will connect to
VM Template name              → the Ubuntu 22.04 template you created
Gateway IP                    → your lab network gateway
3 available static IPs        → one per VM (e.g., 192.168.1.101-103)
```

> **Tip:** Open your vSphere Web Client and note down these names — they must match exactly.

---

## Where to Start — Step by Step

### Step 1: Clone This Repo

```bash
git clone https://github.com/phaniteluguti/legacy-app-vmware-setup.git
cd legacy-app-vmware-setup
```

### Step 2: Install Tools on Your Machine

You need **3 tools** on the machine where you'll run the scripts (your laptop, a jump box, or WSL):

| Tool | What It Does | Minimum Version |
|------|-------------|-----------------|
| Terraform | Creates VMs on VMware vSphere | 1.5+ |
| Ansible | Installs apps & databases on the VMs over SSH | 2.14+ |
| SSH client | Used by Ansible to connect to VMs | any |

Pick your OS below and run **each command one at a time**.

---

#### Option A: Ubuntu / Debian / WSL (Recommended)

**2a-1. Install Terraform:**

```bash
# Download Terraform binary
TERRAFORM_VERSION="1.9.8"
wget "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip"
```

```bash
# Unzip and move to PATH
sudo apt install -y unzip
unzip "terraform_${TERRAFORM_VERSION}_linux_amd64.zip"
sudo mv terraform /usr/local/bin/
rm "terraform_${TERRAFORM_VERSION}_linux_amd64.zip"
```

```bash
# Verify it works
terraform --version
```

**2a-2. Install Ansible:**

```bash
# Install pip if you don't have it
sudo apt install -y python3-pip
```

```bash
# Install Ansible via pip
pip install ansible
```

```bash
# Add pip install location to PATH (required — pip installs to ~/.local/bin which is not on PATH by default)
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

```bash
# Verify Ansible is accessible
ansible --version
```

> **Note:** If `pip install` gives a "externally-managed-environment" error on Ubuntu 23.04+, use:
> ```bash
> pip install ansible --break-system-packages
> ```
> Or install via APT instead: `sudo apt install -y ansible` (no PATH fix needed with APT)

**2a-3. Install Ansible Galaxy Collections:**

These are plugins Ansible needs to manage PostgreSQL, MySQL, etc.

```bash
ansible-galaxy collection install community.postgresql community.mysql community.general
```

**2a-4. Verify SSH is available:**

```bash
# SSH is usually pre-installed on Ubuntu. Verify:
ssh -V
```

If missing: `sudo apt install -y openssh-client`

---

#### Option B: macOS

```bash
# Install both tools via Homebrew
brew install terraform ansible

# Install Ansible Galaxy collections
ansible-galaxy collection install community.postgresql community.mysql community.general
```

---

#### Option C: Windows (without WSL)

> **Important:** Ansible does not run natively on Windows. Choose one of these paths:
>
> - **WSL2 (recommended):** Open PowerShell as Admin → `wsl --install` → reboot → then follow **Option A** above inside WSL
> - **Azure Cloud Shell:** Has Terraform + Ansible pre-installed — no setup needed, just `git clone` and run there
> - **Docker:** Run Ansible from a Linux container on Docker Desktop

---

#### Verify All Tools Are Installed

Run these 3 commands. All must succeed before moving on:

```bash
terraform --version
# Expected: Terraform v1.5.0 or higher

ansible --version
# Expected: ansible [core 2.14.0] or higher

ssh -V
# Expected: OpenSSH_... (any version is fine)
```

If any command says "command not found", go back and redo that installation step.

### Step 3: Prepare a VM Template in vSphere

The automation clones VMs from a template. You create this **once**.

1. **Create a new VM** in vCenter with:
   - Guest OS: Ubuntu 22.04 LTS (64-bit)
   - 2 vCPUs, 4 GB RAM, 40 GB thin-provisioned disk
   - Attach the [Ubuntu 22.04 Server ISO](https://releases.ubuntu.com/22.04/)

2. **Install Ubuntu** with default options. Create a user (e.g., `ubuntu`).

3. **Inside the VM, run:**
   ```bash
   # Update packages
   sudo apt update && sudo apt upgrade -y

   # Install VMware tools (required for guest customization)
   sudo apt install -y open-vm-tools

   # Install SSH server
   sudo apt install -y openssh-server
   sudo systemctl enable ssh

   # Install Python3 (required by Ansible)
   sudo apt install -y python3 python3-pip

   # Add your SSH public key
   mkdir -p ~/.ssh
   echo "YOUR_PUBLIC_KEY_HERE" >> ~/.ssh/authorized_keys
   chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys

   # Clean up for templating
   sudo truncate -s 0 /etc/machine-id
   sudo cloud-init clean
   sudo apt clean
   history -c
   ```

4. **Shut down the VM.**

5. In vCenter: **Right-click the VM → Convert to Template** → name it `ubuntu-2204-template`.

> **Why a template?** Terraform doesn't install an OS from scratch — it clones this template and customizes each clone with a unique hostname and static IP via VMware's guest customization spec. This takes ~2 minutes per VM instead of 30+ minutes for a fresh OS install.

### Step 4: Run the Interactive Setup Wizard

The wizard asks you every question, validates inputs, generates all config files, and runs the full deployment.

**On PowerShell (Windows):**
```powershell
.\scripts\setup-interactive.ps1
```

**On Bash (WSL/Linux/macOS):**
```bash
bash scripts/setup-interactive.sh
```

The wizard walks through 6 sections:

| Section | What It Asks | Example |
|---------|-------------|---------|
| 1. vCenter Connection | Server, username, password | `vcenter.lab.local` |
| 2. vSphere Infrastructure | Datacenter, cluster, datastore, template name | `Datacenter1`, `ubuntu-2204-template` |
| 3. Network Settings | Gateway, DNS, SSH user, key path | `192.168.1.1`, `ubuntu` |
| 4. VM Sizing & IPs | Static IP + CPU/RAM/Disk per VM | `192.168.1.101`, 2 CPU, 4096 MB |
| 5. App & DB Config | Git repos, versions, database passwords | JDK 17, PostgreSQL password |
| 6. Azure Migrate | Install dependency agent? | Yes/No |

After confirming the summary, choose a run mode:

```
[1] Full pipeline (Terraform + Ansible + Verify)   ← recommended for first run
[2] Generate config files only                      ← if you want to review before running
[3] Terraform only                                  ← just provision VMs
[4] Ansible only                                    ← VMs already exist, just deploy apps
```

**Option 1** runs everything end-to-end. Expect **~20-30 minutes** total:
- ~5 min for Terraform to create 3 VMs
- ~1 min waiting for VMs to boot
- ~15-25 min for Ansible to install all apps and databases

### Step 5: Verify Deployment

After the wizard finishes, it runs health checks automatically. You can also verify manually:

```bash
# From your machine (replace IPs with your actual IPs)
curl http://192.168.1.101:8080     # Java PetClinic — should return HTML
curl http://192.168.1.102          # .NET MVC App — should return HTML
curl http://192.168.1.103          # PHP Laravel — should return HTML

# SSH into any VM
ssh ubuntu@192.168.1.101

# Check service status on a VM
systemctl status petclinic         # on java-vm
systemctl status dotnet-app        # on dotnet-vm
systemctl status apache2           # on php-vm
```

---

## Manual Setup (Alternative to Wizard)

If you prefer to configure files manually instead of using the wizard:

```bash
# 1. Copy example configs
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
cp ansible/group_vars/all.yml.example ansible/group_vars/all.yml

# 2. Edit terraform.tfvars — fill in vCenter creds, IPs, template name
#    Edit ansible/group_vars/all.yml — set database passwords

# 3. Provision VMs
cd terraform
terraform init
terraform plan        # review what will be created
terraform apply       # type "yes" to confirm

# 4. Wait ~1 min for VMs to boot, then deploy apps
cd ../ansible
ansible-playbook -i inventory/hosts.ini site.yml -v

# 5. Or use the one-click script
bash scripts/deploy-all.sh all
```

---

## What Gets Deployed

| VM | Hostname | Application | Web Server | Database | Access URL |
|----|----------|------------|------------|----------|------------|
| **Java VM** | legacy-java-vm | Spring PetClinic (Java 17, Spring Boot 2.x) | Embedded Tomcat | PostgreSQL 15 | `http://<java-ip>:8080` |
| **\.NET VM** | legacy-dotnet-vm | ASP.NET Core MVC (.NET 6) | Kestrel + Nginx reverse proxy | SQL Server 2022 Express | `http://<dotnet-ip>` |
| **PHP VM** | legacy-php-vm | Laravel sample app (PHP 8.1) | Apache2 + mod_php | MySQL 8.0 | `http://<php-ip>` |

Each app:
- Runs as a **systemd service** (auto-starts on boot)
- Has its database installed **locally on the same VM** (simulates typical legacy architecture)
- Has **firewall rules** configured for its ports
- Has **sysstat** enabled for performance data collection

---

## Directory Structure

```
legacy-app-vmware-setup/
│
├── scripts/                           # ← START HERE
│   ├── setup-interactive.ps1          # Interactive wizard (PowerShell/Windows)
│   ├── setup-interactive.sh           # Interactive wizard (Bash/WSL/Linux)
│   └── deploy-all.sh                  # Non-interactive orchestration script
│
├── terraform/                         # VM provisioning on vSphere
│   ├── main.tf                        # VM resources + clone from template
│   ├── variables.tf                   # All configurable parameters
│   ├── outputs.tf                     # VM IPs output after apply
│   ├── terraform.tfvars.example       # Template — fill with your values
│   └── templates/
│       └── hosts.ini.tftpl            # Auto-generates Ansible inventory
│
├── ansible/                           # App deployment over SSH
│   ├── site.yml                       # Master playbook (runs everything)
│   ├── requirements.yml               # Ansible Galaxy dependencies
│   ├── inventory/
│   │   └── hosts.ini                  # VM IPs (auto-generated or manual)
│   ├── group_vars/
│   │   └── all.yml.example            # App config + DB passwords template
│   └── playbooks/
│       ├── java-petclinic.yml         # Java 17 + Spring PetClinic + PostgreSQL 15
│       ├── dotnet-app.yml             # .NET 6 + ASP.NET MVC + SQL Server 2022
│       ├── php-app.yml                # PHP 8.1 + Laravel + MySQL 8.0 + Apache2
│       └── azure-migrate-prep.yml     # SSH, sysstat, firewall, dependency agent
│
├── .gitignore                         # Excludes secrets (tfvars, all.yml, keys)
└── README.md                          # This file
```

---

## Configuration Reference

### terraform.tfvars

| Variable | Description | Example |
|----------|-------------|---------|
| `vsphere_server` | vCenter FQDN or IP | `vcenter.lab.local` |
| `vsphere_user` | vCenter login | `administrator@vsphere.local` |
| `vsphere_password` | vCenter password | `MyP@ssw0rd` |
| `vsphere_datacenter` | Datacenter name in vCenter | `Datacenter1` |
| `vsphere_cluster` | Compute cluster name | `Cluster1` |
| `vsphere_datastore` | Datastore for VM disks | `datastore1` |
| `vsphere_network` | Port group / network name | `VM Network` |
| `vm_template_name` | Ubuntu template name in vCenter | `ubuntu-2204-template` |
| `vm_gateway` | Network gateway | `192.168.1.1` |
| `java_vm_ip` | Static IP for Java VM | `192.168.1.101` |
| `dotnet_vm_ip` | Static IP for .NET VM | `192.168.1.102` |
| `php_vm_ip` | Static IP for PHP VM | `192.168.1.103` |

### ansible/group_vars/all.yml

| Variable | Description | Default |
|----------|-------------|---------|
| `java_version` | JDK version | `17` |
| `postgres_password` | PostgreSQL password | *(you set this)* |
| `dotnet_sdk_version` | .NET SDK version | `6.0` |
| `mssql_sa_password` | SQL Server SA password (min 8 chars, needs uppercase+number+symbol) | *(you set this)* |
| `php_version` | PHP version | `8.1` |
| `mysql_root_password` | MySQL root password | *(you set this)* |
| `install_azure_migrate_agent` | Install dependency agent on VMs | `false` |

---

## Azure Migrate — Next Steps

After the VMs are deployed and running, connect them to Azure Migrate:

### 1. Create an Azure Migrate Project
```
Azure Portal → Azure Migrate → Create project
```

### 2. Deploy the Azure Migrate Appliance
- Download the Azure Migrate appliance OVA from the portal
- Deploy it on the same vSphere/ESXi as your legacy VMs
- Configure it with your vCenter credentials

### 3. Start Discovery
- The appliance connects to vCenter and discovers your 3 VMs
- It collects hardware specs, OS info, installed apps, and dependencies
- Discovery runs continuously — let it collect data for **at least 24 hours** for accurate sizing

### 4. Run Assessment
- In the Azure Migrate portal, create an assessment
- Choose target: **Azure VM** (IaaS) or **Azure App Service / SQL** (PaaS)
- Review right-sizing recommendations, cost estimates, and migration readiness

### What Azure Migrate Will Find

| VM | Discovered Apps | Discovered DBs | Dependencies |
|----|----------------|----------------|-------------|
| legacy-java-vm | Java 17, Spring Boot, Tomcat | PostgreSQL 15 | → PostgreSQL (localhost:5432) |
| legacy-dotnet-vm | .NET 6, ASP.NET Core, Nginx | SQL Server 2022 | → SQL Server (localhost:1433) |
| legacy-php-vm | PHP 8.1, Apache2, Laravel | MySQL 8.0 | → MySQL (localhost:3306) |

---

## Troubleshooting

### "command not found" after installing Ansible via pip
```
ansible: command not found
```
- `pip install` puts binaries in `~/.local/bin` which is not on PATH by default
- Fix:
  ```bash
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
  source ~/.bashrc
  ```
- Then retry: `ansible --version`

### Terraform can't connect to vCenter
```
Error: ServerFaultCode: Cannot complete login due to an incorrect user name or password
```
- Verify `vsphere_server`, `vsphere_user`, `vsphere_password` in `terraform.tfvars`
- Ensure your machine can reach the vCenter on port 443: `curl -k https://vcenter.example.com`
- If using self-signed certs, ensure `vsphere_allow_unverified_ssl = true`

### Template not found
```
Error: virtual machine "ubuntu-2204-template" not found
```
- The `vm_template_name` must match the template name in vCenter **exactly** (case-sensitive)
- Check: vCenter → VMs and Templates view → find your template

### Ansible SSH connection fails
```
UNREACHABLE! => {"msg": "Failed to connect to the host via ssh"}
```
- Ensure VMs are booted and have IPs: check in vCenter → VM → Summary → IP Address
- Test SSH manually: `ssh -i ~/.ssh/id_rsa ubuntu@192.168.1.101`
- Verify the SSH public key is in the VM template's `~/.ssh/authorized_keys`
- Check firewall: `ufw status` on the VM

### SQL Server SA password rejected
```
Setup for Microsoft SQL Server failed with error code 1
```
- SA password must meet complexity: minimum 8 characters, with uppercase, lowercase, number, and symbol
- Example: `Str0ngP@ss!2024`

### Java app fails to start
```
petclinic.service: Main process exited, code=exited, status=1/FAILURE
```
- Check logs: `journalctl -u petclinic -f`
- Common cause: PostgreSQL not running — `systemctl status postgresql`
- Common cause: Port 8080 in use — `ss -tlnp | grep 8080`

### Re-running safely
- **Terraform:** `terraform apply` is idempotent — safe to re-run
- **Ansible:** All playbooks are idempotent — safe to re-run
- **Wizard:** Running the wizard again overwrites config files, so confirm backup if needed

---

## Cleanup

### Destroy only the VMs (keep config)
```bash
cd terraform
terraform destroy    # type "yes" to confirm
```

### Remove all generated files
```bash
rm -f terraform/terraform.tfvars
rm -f terraform/tfplan
rm -f ansible/group_vars/all.yml
rm -f ansible/inventory/hosts.ini
```

### Remove from vSphere manually
If Terraform state is lost, delete VMs from vCenter: right-click → Delete from Disk.

---

## Security Notes

- `terraform.tfvars` and `ansible/group_vars/all.yml` contain passwords — both are in `.gitignore` and will **not** be committed
- The interactive wizard collects passwords via masked/secure input
- Database passwords should meet complexity requirements for your organization
- The SQL Server password **must** include uppercase, lowercase, number, and special character
- For production use, consider Ansible Vault for encrypting secrets: `ansible-vault encrypt group_vars/all.yml`
