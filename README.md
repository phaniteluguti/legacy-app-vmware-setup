# VMware Legacy App Lab — Azure Migrate Assessment Setup

Automated deployment of legacy applications (Java, .NET, PHP) on VMware VMs to simulate a real-world on-premises environment for **Azure Migrate discovery and assessment**.

Choose which **apps** to deploy (Java, .NET, PHP, or all), which **OS** (Linux, Windows, or both), and which **architecture** (Single-VM or 3-Tier) — the interactive wizard handles the rest: provisioning VMs on vSphere via Terraform, deploying full web + database stacks via Ansible, and configuring everything for Azure Migrate agentless discovery.

---

## Table of Contents

1. [What This Does](#what-this-does)
2. [Architecture](#architecture)
   - [Single-VM Mode](#single-vm-mode)
   - [3-Tier Mode](#3-tier-mode)
3. [Prerequisites](#prerequisites)
4. [Where to Start — Step by Step](#where-to-start--step-by-step)
   - [Step 1: Clone This Repo](#step-1-clone-this-repo)
   - [Step 2: Install Tools on Your Machine](#step-2-install-tools-on-your-machine)
   - [Step 3: Prepare a VM Template in vSphere](#step-3-prepare-a-vm-template-in-vsphere)
   - [Step 3b: Prepare a Windows Template (Optional)](#step-3b-prepare-a-windows-template-optional)
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
| **Select** | Wizard | Choose apps (Java/.NET/PHP/All), OS (Linux/Windows/Both), and architecture (Single-VM/3-Tier) |
| **Provision** | Terraform | Clones VM templates in vSphere into VMs with static IPs |
| **Deploy** | Ansible | Installs selected app stacks on each VM |
| **Prepare** | Ansible | Enables SSH/WinRM, sysstat, firewall rules, and optional Azure Migrate Dependency Agent |
| **Assess** | Azure Migrate | You point the Azure Migrate appliance at your vCenter and discover all VMs |

---

## Architecture

### Single-VM Mode

Each app runs on a single VM with the application and database co-located (typical legacy monolith pattern).

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                              VMware vSphere                                  │
│                                                                              │
│  Linux Single-VM (deploy_mode = linux)                                       │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐                       │
│  │  VM: java-vm  │  │  VM: dotnet-vm│  │  VM: php-vm  │                      │
│  │  Ubuntu 22.04 │  │  Ubuntu 22.04 │  │  Ubuntu 22.04│                      │
│  │  Spring       │  │  ASP.NET Core │  │  Laravel     │                      │
│  │  PetClinic    │  │  MVC + Nginx  │  │  + Apache2   │                      │
│  │  (Java 17)    │  │  (.NET 6)     │  │  (PHP 8.1)   │                      │
│  │  PostgreSQL 15│  │  SQL Server   │  │  MySQL 8.0   │                      │
│  │               │  │  2022 Express │  │              │                      │
│  └──────────────┘  └──────────────┘  └──────────────┘                       │
│                                                                              │
│  Windows Single-VM (deploy_mode = windows)                                   │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐                       │
│  │ VM: win-java  │  │ VM: win-dotnet│  │ VM: win-php  │                      │
│  │ Win Srv 2019  │  │ Win Srv 2019  │  │ Win Srv 2019 │                      │
│  │ Spring        │  │ ASP.NET       │  │ Laravel      │                      │
│  │ PetClinic     │  │ Framework     │  │ + IIS        │                      │
│  │ (Java 17)     │  │ IIS (.NET 4.5)│  │ (PHP + CGI)  │                      │
│  │ PostgreSQL 15 │  │ SQL Server    │  │ MySQL        │                      │
│  │               │  │ 2019 Express  │  │              │                      │
│  └──────────────┘  └──────────────┘  └──────────────┘                       │
│                                                                              │
│         Per-app selection: deploy 1, 2, or all 3 apps                        │
│         "Both" OS: deploys Linux AND Windows VMs simultaneously              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### 3-Tier Mode

Each app is split across 3 VMs: Frontend (web server / reverse proxy), App Server, and Database — simulating enterprise multi-tier architectures for Azure Migrate to discover inter-VM dependencies.

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                              VMware vSphere                                  │
│                                                                              │
│  Linux 3-Tier (deploy_mode = linux-3tier)      per app: 3 VMs               │
│                                                                              │
│  Java Stack:                                                                 │
│  ┌─────────────┐   ┌─────────────┐   ┌─────────────┐                       │
│  │  Frontend    │──▶│  App Server  │──▶│  Database    │                      │
│  │  Angular+Nginx│  │  REST API   │   │  PostgreSQL  │                      │
│  │  :80         │   │  :9966      │   │  :5432       │                      │
│  └─────────────┘   └─────────────┘   └─────────────┘                       │
│                                                                              │
│  .NET Stack:                                                                 │
│  ┌─────────────┐   ┌─────────────┐   ┌─────────────┐                       │
│  │  Frontend    │──▶│  App Server  │──▶│  Database    │                      │
│  │  Nginx proxy │   │  ASP.NET    │   │  SQL Server  │                      │
│  │  :80         │   │  :5000      │   │  :1433       │                      │
│  └─────────────┘   └─────────────┘   └─────────────┘                       │
│                                                                              │
│  PHP Stack:                                                                  │
│  ┌─────────────┐   ┌─────────────┐   ┌─────────────┐                       │
│  │  Frontend    │──▶│  App Server  │──▶│  Database    │                      │
│  │  Nginx proxy │   │  Laravel    │   │  MySQL       │                      │
│  │  :80         │   │  :8000      │   │  :3306       │                      │
│  └─────────────┘   └─────────────┘   └─────────────┘                       │
│                                                                              │
│  Windows 3-Tier (deploy_mode = windows-3tier)  per app: 3 VMs               │
│  Same layout with IIS+ARR frontends, IIS/NSSM app servers, Windows DBs      │
│                                                                              │
│  Per-app selection: deploy 1, 2, or all 3 stacks (3 to 9 VMs per OS)        │
│  "Both" OS: deploys Linux AND Windows 3-tier simultaneously (up to 18 VMs)  │
└──────────────────────────────────────────────────────────────────────────────┘
         │
         ▼  Azure Migrate Appliance discovers all VMs and inter-VM dependencies
┌──────────────────────────────────────────────────────────────────────────────┐
│  Migration Targets:                                                          │
│  Azure IaaS (VMs)           │  Azure PaaS                                    │
│  • Azure VMs                │  • App Service                                 │
│  • Managed Disks            │  • Azure SQL / Postgres / MySQL                │
│  • NSGs, VNets              │  • Azure Container Apps                        │
└──────────────────────────────────────────────────────────────────────────────┘
```

### VM Count Summary

| App Selection | Architecture | Linux | Windows | Both |
|--------------|-------------|-------|---------|------|
| Single app | Single-VM | 1 VM | 1 VM | 2 VMs |
| Single app | 3-Tier | 3 VMs | 3 VMs | 6 VMs |
| All apps | Single-VM | 3 VMs | 3 VMs | 6 VMs |
| All apps | 3-Tier | 9 VMs | 9 VMs | 18 VMs |

---

## Prerequisites

### On Your Machine (the "control node")

| Tool | Version | How to Install | Why Needed |
|------|---------|----------------|------------|
| **Terraform** | >= 1.5 | [terraform.io/install](https://developer.hashicorp.com/terraform/install) | Creates VMs on vSphere |
| **Ansible** | >= 2.14 | `pip install ansible` or use WSL on Windows | Deploys apps over SSH/WinRM |
| **SSH client** | any | Built into Windows 10+, macOS, Linux | Ansible connects to Linux VMs |
| **pywinrm** | any | `pip install pywinrm` | Ansible connects to Windows VMs (only needed if deploying Windows VM) |
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
| **Windows Server 2019/2022 template** | Required for Windows mode — a template with WinRM enabled (see [Step 3b](#step-3b-prepare-a-windows-template-optional)) |
| **Network** | A port group with DHCP or a static IP range you can assign to VMs (1-18 depending on selections) |
| **SSH access** | Either password auth enabled in template, or SSH key pair (public key in template, private key on your machine) |

### Information You'll Need to Gather

Before running the wizard, collect these from your vCenter:

```
vCenter server address        → e.g., vcenter.mycompany.com
vCenter username/password     → e.g., administrator@vsphere.local
Datacenter name               → visible in vCenter inventory tree
Cluster name                  → the compute cluster under the datacenter
Datastore name                → where VM disks will be stored
Network/Port Group name       → the network VMs will connect to
Linux VM Template name        → the Ubuntu 22.04 template you created
Windows VM Template name      → (Windows mode) your Windows Server 2019/2022 template
Gateway IP                    → your lab network gateway
Available static IPs          → 1-18 IPs depending on app/OS/architecture selections
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
# Install pip and sshpass (sshpass is needed for password-based SSH auth)
sudo apt install -y python3-pip sshpass
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

These are plugins Ansible needs to manage PostgreSQL, MySQL, Windows, etc.

```bash
ansible-galaxy collection install community.postgresql community.mysql community.general ansible.windows
```

**2a-4. Install pywinrm (needed for Windows VMs):**

```bash
pip install pywinrm
```

**2a-5. Verify SSH is available:**

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
ansible-galaxy collection install community.postgresql community.mysql community.general ansible.windows

# Install pywinrm (for Windows VM support)
pip install pywinrm
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

2. **Install Ubuntu** with default options. Create a user (e.g., `ubuntu`) with a password you remember.

3. **Inside the VM, run:**
   ```bash
   # Update packages
   sudo apt update && sudo apt upgrade -y

   # Install VMware tools (required for guest customization)
   sudo apt install -y open-vm-tools

   # Install SSH server
   sudo apt install -y openssh-server
   sudo systemctl enable ssh

   # Enable password-based SSH login (so Ansible can connect without keys)
   sudo sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config
   sudo systemctl restart ssh

   # Install Python3 (required by Ansible)
   sudo apt install -y python3 python3-pip

   # Clean up for templating
   sudo truncate -s 0 /etc/machine-id
   sudo cloud-init clean
   sudo apt clean
   history -c
   ```

   > **Optional — SSH key auth instead:** If you prefer key-based auth, skip the `PasswordAuthentication` line above and instead do:
   > ```bash
   > mkdir -p ~/.ssh
   > echo "YOUR_PUBLIC_KEY_HERE" >> ~/.ssh/authorized_keys
   > chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys
   > ```
   > Then choose "SSH key" in the wizard (Step 4). Most users can just use password auth — it's simpler.

4. **Shut down the VM.**

5. In vCenter: **Right-click the VM → Convert to Template** → name it `ubuntu-2204-template`.

> **Why a template?** Terraform doesn't install an OS from scratch — it clones this template and customizes each clone with a unique hostname and static IP via VMware's guest customization spec. This takes ~2 minutes per VM instead of 30+ minutes for a fresh OS install.

### Step 3b: Prepare a Windows Template (Optional)

If you want to deploy Windows legacy apps, you need a Windows Server template with WinRM enabled. Both **Windows Server 2019** and **2022** are supported.

1. **Create a new VM** in vCenter with:
   - Guest OS: Windows Server 2019 or 2022 (64-bit)
   - 2 vCPUs, 4 GB RAM, 60 GB thin-provisioned disk
   - Attach the Windows Server ISO

2. **Install Windows Server** with Desktop Experience. Set an Administrator password.

3. **Inside the VM, open PowerShell as Administrator and run:**
   ```powershell
   # Enable WinRM HTTP listener for Ansible connectivity
   winrm quickconfig -force
   winrm set winrm/config/service '@{AllowUnencrypted="true"}'
   winrm set winrm/config/service/auth '@{Basic="true"}'
   Enable-PSRemoting -Force

   # Open firewall for WinRM HTTP (port 5985)
   New-NetFirewallRule -Name "WinRM-HTTP" -DisplayName "WinRM HTTP" -Protocol TCP -LocalPort 5985 -Action Allow

   # Install VMware Tools (required for guest customization)
   # Mount the VMware Tools ISO from vCenter and run setup.exe, or:
   # Install-WindowsFeature -Name NET-Framework-45-Core

   # Clean up for templating
   # Run sysprep if you want unique SIDs:
   # C:\Windows\System32\Sysprep\sysprep.exe /generalize /oobe /shutdown
   ```

   > **Note:** The template must have VMware Tools installed for Terraform's guest customization (setting hostname and static IP) to work. Mount the VMware Tools ISO from vCenter → VM → Install VMware Tools.

4. **Shut down the VM.**

5. In vCenter: **Right-click the VM → Convert to Template** → name it `windows-2019-template`.

> **Tip:** If you already have a Windows Server 2019 template from another project, just make sure WinRM is configured on port 5986 (HTTPS) or 5985 (HTTP). The wizard will ask for the template name.

### Step 4: Run the Interactive Setup Wizard

The wizard walks through a **3-step selection** followed by infrastructure and app configuration. It validates inputs, generates all config files, and optionally runs the full deployment.

**On PowerShell (Windows):**
```powershell
.\scripts\setup-interactive.ps1
```

**On Bash (WSL/Linux/macOS):**
```bash
bash scripts/setup-interactive.sh
```

#### The 3-Step Selection Flow

```
Step 1: Choose Application(s)
  1) Java     — Spring PetClinic + PostgreSQL
  2) .NET     — ASP.NET + SQL Server
  3) PHP      — Laravel + MySQL
  4) All      — Java + .NET + PHP (all three)

Step 2: Choose Operating System
  1) Linux    — Ubuntu 22.04 VMs
  2) Windows  — Windows Server 2019 VMs
  3) Both     — Deploy on Linux AND Windows

Step 3: Choose Architecture
  1) Single-VM  — All-in-one: app + database on same VM
  2) 3-Tier     — Separate Frontend, App Server, and Database VMs
```

After the 3-step selection, the wizard collects:

| Section | What It Asks | Example |
|---------|-------------|---------|
| vCenter Connection | Server, username, password | `vcenter.lab.local` |
| vSphere Infrastructure | Datacenter, cluster, datastore, template name(s) | `Datacenter1`, `ubuntu-2204-template` |
| Network Settings | Gateway, DNS, SSH user, key path, Windows password | `192.168.1.1`, `ubuntu` |
| VM Sizing & IPs | Static IP + CPU/RAM/Disk per VM; 3-Tier offers same-for-all, per-tier, or recommended defaults | `192.168.1.101`, 2 CPU, 4096 MB |
| App & DB Config | Git repos, versions, database passwords (only for selected apps) | JDK 17, PostgreSQL password |
| Azure Migrate | Install dependency agent? | Yes/No |

After confirming the summary, choose a run mode:

```
[1] Full pipeline (Terraform + Ansible + Verify)   ← recommended for first run
[2] Stop here — review config files before running  ← default
[3] Terraform only                                  ← just provision VMs
[4] Ansible only                                    ← VMs already exist, just deploy apps
[5] Resume Ansible                                  ← retry failed hosts on re-run
[6] Destroy all VMs                                 ← clean up a previous run
```

> **Re-running the wizard:** All prompts pre-fill with previously saved values — including app, OS, and architecture selections. Just press Enter to keep them, or type a new value. Passwords are always re-prompted.

> **Quick mode (`--quick`):** If you've already run the wizard once and just want to re-deploy with the same settings, use `--quick` to skip all saved prompts and only enter passwords:
> ```bash
> bash scripts/setup-interactive.sh --quick
> ```
> This loads your previous app/OS/architecture selections, vCenter, infrastructure, network, VM sizing, IPs, and app config from the saved `terraform.tfvars` and `group_vars/all.yml`. Only passwords are prompted (vCenter, SSH, Windows admin, database passwords) since they are never saved to disk.

> **"Both" OS mode:** The pipeline runs Terraform + Ansible once for each OS. For example, choosing "All apps + Both + 3-Tier" provisions 9 Linux VMs then 9 Windows VMs (18 total).

**Option 1** runs everything end-to-end. Expect:
- **Single-VM, one app:** ~10-15 minutes
- **Single-VM, all apps:** ~20-35 minutes
- **3-Tier, all apps:** ~30-50 minutes
- **Both OS:** Double the above (runs sequentially per OS)

### Step 5: Verify Deployment

After the wizard finishes, it runs health checks automatically. You can also verify manually:

```bash
# From your machine (replace IPs with your actual IPs)
curl http://192.168.1.101:8080     # Java PetClinic — should return HTML
curl http://192.168.1.102          # .NET App — should return HTML
curl http://192.168.1.103          # PHP Laravel — should return HTML

# Linux mode: SSH into any VM
ssh ubuntu@192.168.1.101

# Windows mode: RDP into any VM
# Use Remote Desktop to connect to 192.168.1.101, .102, or .103

# Check service status (Linux mode)
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

# 3. Provision VMs (select workspace matching your deploy_mode)
cd terraform
terraform init
terraform workspace select -or-create linux   # or: windows
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

### Linux Single-VM (deploy_mode = linux)

| VM | Hostname (default) | OS | Application | Web Server | Database | Access URL |
|----|----------|-----|------------|------------|----------|------------|
| **Java VM** | legacy-java-vm | Ubuntu 22.04 | Spring PetClinic (Java 17, Spring Boot) | Embedded Tomcat | PostgreSQL 15 | `http://<java-ip>:8080` |
| **\.NET VM** | legacy-dotnet-vm | Ubuntu 22.04 | ASP.NET Core MVC (.NET 8) | Kestrel + Nginx reverse proxy | SQL Server 2022 Express | `http://<dotnet-ip>` |
| **PHP VM** | legacy-php-vm | Ubuntu 22.04 | Laravel sample app (PHP 8.1) | Apache2 + mod_php | MySQL 8.0 | `http://<php-ip>` |

### Windows Single-VM (deploy_mode = windows)

| VM | Hostname (default) | OS | Application | Web Server | Database | Access URL |
|----|----------|-----|------------|------------|----------|------------|
| **Win Java VM** | legacy-win-java-vm | Windows Server 2019 | Spring PetClinic (Java 17, Spring Boot) | NSSM service | PostgreSQL 15 | `http://<java-ip>:8080` |
| **Win .NET VM** | legacy-win-dotnet-vm | Windows Server 2019 | ASP.NET Framework Web Forms (.NET 4.5) | IIS 10 | SQL Server 2019 Express | `http://<dotnet-ip>` |
| **Win PHP VM** | legacy-win-php-vm | Windows Server 2019 | Laravel (PHP + IIS FastCGI) | IIS 10 | MySQL | `http://<php-ip>` |

### Linux 3-Tier (deploy_mode = linux-3tier)

Each app is split across 3 VMs — 9 VMs total for all apps:

| Stack | Frontend VM | App Server VM | Database VM |
|-------|------------|---------------|-------------|
| **Java** | Angular + Nginx (:80) | REST API Spring Boot (:9966) | PostgreSQL 15 (:5432) |
| **.NET** | Nginx reverse proxy (:80) | eShopOnWeb ASP.NET Core 8.0 Kestrel (:5000) | SQL Server 2022 Express (:1433) |
| **PHP** | Nginx reverse proxy (:80) | Laravel artisan (:8000) | MySQL 8.0 (:3306) |

### Windows 3-Tier (deploy_mode = windows-3tier)

| Stack | Frontend VM | App Server VM | Database VM |
|-------|------------|---------------|-------------|
| **Java** | IIS + ARR reverse proxy (:80) | NSSM service (:9966) | PostgreSQL 15 (:5432) |
| **.NET** | IIS + ARR reverse proxy (:80) | IIS ASP.NET (:80) | SQL Server Express (:1433) |
| **PHP** | IIS + ARR reverse proxy (:80) | IIS + PHP FastCGI (:80) | MySQL (:3306) |

### Per-App Selection

You don't have to deploy all 3 apps. The wizard lets you choose:
- **Java only** — deploys only Java/PetClinic VMs (`deploy_java = true`)
- **.NET only** — deploys only .NET VMs (`deploy_dotnet = true`)
- **PHP only** — deploys only PHP/Laravel VMs (`deploy_php = true`)
- **All** — deploys all three (default)

Each app:
- Runs as a **systemd service** (Linux) or **Windows service / IIS site** (Windows) — auto-starts on boot
- Has its database either **co-located** (Single-VM) or on a **separate database VM** (3-Tier)
- Has **firewall rules** configured for its ports
- Has **sysstat** enabled for performance data collection (Linux VMs)
- Has **RDP** and **WinRM** enabled for Azure Migrate discovery (Windows VMs)

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
│   ├── main.tf                        # VM resources — per-app filtering with deploy_java/dotnet/php
│   ├── variables.tf                   # All configurable parameters (incl. per-app booleans)
│   ├── outputs.tf                     # VM IPs output after apply
│   ├── terraform.tfvars.example       # Template — fill with your values
│   └── templates/
│       └── hosts.ini.tftpl            # Auto-generates Ansible inventory (all 4 modes)
│
├── ansible/                           # App deployment over SSH (Linux) / WinRM (Windows)
│   ├── site.yml                       # Master playbook — single-VM modes
│   ├── requirements.yml               # Ansible Galaxy dependencies
│   ├── inventory/
│   │   └── hosts.ini                  # VM IPs (auto-generated or manual)
│   ├── group_vars/
│   │   └── all.yml.example            # App config + DB passwords template
│   └── playbooks/
│       ├── java-petclinic.yml         # Linux: Java 17 + Spring PetClinic + PostgreSQL
│       ├── dotnet-app.yml             # Linux: .NET 6 + ASP.NET MVC + SQL Server
│       ├── php-app.yml                # Linux: PHP 8.1 + Laravel + MySQL + Apache2
│       ├── win-java-petclinic.yml     # Windows: Java PetClinic + PostgreSQL
│       ├── win-iis-app.yml            # Windows: IIS + ASP.NET Framework + SQL Server
│       ├── win-php-app.yml            # Windows: PHP Laravel + MySQL + IIS
│       ├── azure-migrate-prep.yml     # SSH, sysstat, firewall, dependency agent
│       └── 3tier/                     # 3-Tier architecture playbooks
│           ├── site-3tier.yml         # Master playbook — Linux 3-tier
│           ├── site-3tier-win.yml     # Master playbook — Windows 3-tier
│           ├── java-frontend.yml      # Linux: Angular + Nginx frontend
│           ├── java-appserver.yml     # Linux: REST API Spring Boot
│           ├── java-database.yml      # Linux: PostgreSQL server
│           ├── dotnet-frontend.yml    # Linux: Nginx reverse proxy
│           ├── dotnet-appserver.yml   # Linux: eShopOnWeb ASP.NET Core 8.0 Kestrel
│           ├── dotnet-database.yml    # Linux: SQL Server 2022 Express
│           ├── php-frontend.yml       # Linux: Nginx reverse proxy
│           ├── php-appserver.yml      # Linux: Laravel artisan
│           ├── php-database.yml       # Linux: MySQL server
│           ├── win-java-frontend.yml  # Windows: IIS + ARR
│           ├── win-java-appserver.yml # Windows: NSSM Java service
│           ├── win-java-database.yml  # Windows: PostgreSQL
│           ├── win-dotnet-frontend.yml # Windows: IIS + ARR
│           ├── win-dotnet-appserver.yml # Windows: IIS ASP.NET
│           ├── win-dotnet-database.yml # Windows: SQL Server
│           ├── win-php-frontend.yml   # Windows: IIS + ARR
│           ├── win-php-appserver.yml   # Windows: IIS + PHP
│           └── win-php-database.yml   # Windows: MySQL
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
| `java_vm_ip` | Static IP for Java VM (both modes) | `192.168.1.101` |
| `java_vm_hostname` | Hostname for the Java VM | `legacy-java-vm` |
| `dotnet_vm_ip` | Static IP for .NET VM (both modes) | `192.168.1.102` |
| `dotnet_vm_hostname` | Hostname for the .NET VM | `legacy-dotnet-vm` |
| `php_vm_ip` | Static IP for PHP VM (both modes) | `192.168.1.103` |
| `php_vm_hostname` | Hostname for the PHP VM | `legacy-php-vm` |
| `deploy_mode` | Deployment mode | `linux`, `windows`, `linux-3tier`, or `windows-3tier` |
| `deploy_java` | Deploy Java app VMs | `true` |
| `deploy_dotnet` | Deploy .NET app VMs | `true` |
| `deploy_php` | Deploy PHP app VMs | `true` |
| `win_template_name` | Windows Server template name in vCenter | `windows-2019-template` |
| `win_admin_password` | Windows Administrator password | `MyP@ssw0rd` |
| `java_fe_hostname` | Hostname for Java frontend VM (3-tier) | `3t-java-fe` |
| `java_app_hostname` | Hostname for Java app server VM (3-tier) | `3t-java-app` |
| `java_db_hostname` | Hostname for Java database VM (3-tier) | `3t-java-db` |
| `dotnet_fe_hostname` | Hostname for .NET frontend VM (3-tier) | `3t-dotnet-fe` |
| `dotnet_app_hostname` | Hostname for .NET app server VM (3-tier) | `3t-dotnet-app` |
| `dotnet_db_hostname` | Hostname for .NET database VM (3-tier) | `3t-dotnet-db` |
| `php_fe_hostname` | Hostname for PHP frontend VM (3-tier) | `3t-php-fe` |
| `php_app_hostname` | Hostname for PHP app server VM (3-tier) | `3t-php-app` |
| `php_db_hostname` | Hostname for PHP database VM (3-tier) | `3t-php-db` |

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

**Single-VM Mode (Linux):**

| VM | Discovered Apps | Discovered DBs | Dependencies |
|----|----------------|----------------|-------------|
| legacy-java-vm | Java 17, Spring Boot, Tomcat | PostgreSQL 15 | → PostgreSQL (localhost:5432) |
| legacy-dotnet-vm | .NET 8, ASP.NET Core, Nginx | SQL Server 2022 | → SQL Server (localhost:1433) |
| legacy-php-vm | PHP 8.1, Apache2, Laravel | MySQL 8.0 | → MySQL (localhost:3306) |

**Single-VM Mode (Windows):**

| VM | Discovered Apps | Discovered DBs | Dependencies |
|----|----------------|----------------|-------------|
| legacy-win-java-vm | Java 17, Spring Boot, NSSM | PostgreSQL 15 | → PostgreSQL (localhost:5432) |
| legacy-win-dotnet-vm | .NET 4.5, IIS 10, ASP.NET | SQL Server 2019 | → SQL Server (localhost:1433) |
| legacy-win-php-vm | PHP, IIS 10, Laravel | MySQL | → MySQL (localhost:3306) |

**3-Tier Mode — Inter-VM Dependencies (the key value-add):**

| Frontend VM | Depends On | App Server VM | Depends On | Database VM |
|------------|-----------|---------------|-----------|-------------|
| java-fe (Nginx :80) | → | java-app (:9966) | → | java-db (PostgreSQL :5432) |
| dotnet-fe (Nginx :80) | → | dotnet-app (:5000) | → | dotnet-db (SQL Server :1433) |
| php-fe (Nginx :80) | → | php-app (:8000) | → | php-db (MySQL :3306) |

Azure Migrate will discover these cross-VM network connections and map them as **application dependencies** — critical for planning which VMs must migrate together.

### 3-Tier Application Details

| Stack | Application | Source | Notes |
|-------|-------------|--------|-------|
| **Java** | Spring PetClinic (Angular frontend + REST API) | [`spring-petclinic-angular`](https://github.com/spring-petclinic/spring-petclinic-angular) + [`spring-petclinic-rest`](https://github.com/spring-petclinic/spring-petclinic-rest) | Frontend: Angular SPA via Nginx; API: Spring Boot :9966; Swagger UI at `/petclinic/`; requires `postgresql,spring-data-jpa` profiles |
| **.NET** | eShopOnWeb (ASP.NET Core 8.0) | [`eShopOnWeb`](https://github.com/dotnet-architecture/eShopOnWeb) (archived, frozen at .NET 8) | Runs with `ASPNETCORE_ENVIRONMENT=Docker`; uses `signed-by` GPG key for SQL Server APT repo |
| **PHP** | Laravel sample app | [`laravel`](https://github.com/laravel/laravel) | PHP-FPM behind Nginx; MySQL remote DB |

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

### Java 3-tier: REST API won't start (PetRepository bean not found)
```
No qualifying bean of type 'PetRepository'
```
- Spring PetClinic REST requires **both** `postgresql` AND `spring-data-jpa` profiles
- Verify the systemd unit has: `--spring.profiles.active=postgresql,spring-data-jpa`

### Java 3-tier: "relation already exists" on re-deploy
```
org.postgresql.util.PSQLException: ERROR: relation "idx_vets_last_name" already exists
```
- Spring's SQL init scripts don't use `IF NOT EXISTS` for indexes
- The playbook sets `spring.sql.init.continue-on-error=true` to handle this — safe to ignore

### Java 3-tier: PostgreSQL password authentication failed
```
FATAL: password authentication failed for user "petclinic"
```
- If the database VM was previously deployed with a different password, the user already exists with the old password
- The playbook runs `ALTER USER` to sync the password on every run — re-run the database playbook
- For PostgreSQL 15+, the `public` schema requires explicit `GRANT ALL ON SCHEMA public` for non-superusers

### Re-running safely
- **Terraform:** `terraform apply` is idempotent — safe to re-run
- **Ansible:** All playbooks are idempotent — safe to re-run
- **Wizard:** Running the wizard again overwrites config files, so confirm backup if needed
- **Quick re-run:** `bash scripts/setup-interactive.sh --quick` — reuses all saved config, only prompts for passwords
- **Failed run?** Run `bash scripts/setup-interactive.sh --destroy` to clean up, then re-run

### Resuming after Ansible failure
If Ansible fails (e.g., SSH connection timeout, missing sshpass), you can resume without re-running Terraform:

```bash
# Resume — automatically detects previous app/OS/architecture selections
# For "both" OS mode, resumes each OS sequentially
bash scripts/setup-interactive.sh --resume
```

Or re-run the wizard and pick **option 5 (Resume Ansible)** at the menu.

The script uses Ansible retry files (`.retry`) to track which hosts failed and only re-runs against those hosts.

**Common fix before resuming:** If you see `"you must install the sshpass program"`, run:
```bash
sudo apt install -y sshpass
```

### vSphere tags error (404 Not Found)
```
Error: error attaching tags to object ID "vm-xxxxx": 404 Not Found
```
- This means your vCenter doesn't support the tags API (common on AVS)
- Pull the latest code — this has been fixed (tags removed)

### Windows VM: WinRM connection fails
```
UNREACHABLE! => {"msg": "winrm connection error"}
```
- Ensure WinRM is configured in the Windows template (see [Step 3b](#step-3b-prepare-a-windows-template-optional))
- Test connectivity: `curl -k https://<win-ip>:5986/wsman`
- Verify `pywinrm` is installed: `pip install pywinrm`
- Try HTTP (port 5985) if HTTPS fails — update `ansible_port` in inventory to `5985`

### Windows VM: SQL Server download hangs or fails
- The SQL Server 2019 Express installer is ~800 MB and needs internet access
- Ensure the Windows VM can reach `go.microsoft.com` and `download.microsoft.com`
- If behind a proxy, configure the proxy in the Windows template before templating

---

## Cleanup

### CLI Flags

| Flag | Description |
|------|-------------|
| *(none)* | Full interactive wizard — prompts for everything |
| `--quick` | Reuse saved config from previous run, only prompt for passwords |
| `--resume` | Retry failed Ansible hosts without re-running Terraform |
| `--destroy` | Destroy all VMs across all workspaces |

### Quick destroy via wizard
```bash
# Fastest way — skips the wizard, goes straight to destroy
# Automatically destroys all workspaces from your last deployment (including "both" OS mode)
bash scripts/setup-interactive.sh --destroy
```

Or re-run the wizard and pick **option 6** at the end.

### Destroy manually (keep config)
```bash
cd terraform
terraform init
terraform workspace select linux    # or: windows, linux-3tier, windows-3tier
terraform destroy    # type "yes" to confirm — only destroys VMs in this workspace
```

> **"Both" OS cleanup:** If you deployed with "Both" OS, you need to destroy each workspace separately (e.g., `linux` and `windows`), or use `--destroy` which handles this automatically.

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
