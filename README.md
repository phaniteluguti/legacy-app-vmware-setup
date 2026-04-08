# VMware Legacy App Lab — Azure Migrate Assessment Setup

Automated deployment of legacy applications (Java, .NET, PHP) on VMware VMs to simulate a real-world on-premises environment for **Azure Migrate discovery and assessment**.

This repo provisions either **3 Linux VMs** (Java, .NET, PHP) **or 3 Windows Server VMs** (Java, .NET, PHP), installs a full web + database stack on each, and configures them for Azure Migrate agentless discovery — all from a single interactive wizard.

---

## Table of Contents

1. [What This Does](#what-this-does)
2. [Architecture](#architecture)
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
| **Provision** | Terraform | Clones Ubuntu 22.04 and Windows Server 2019 templates in vSphere into VMs with static IPs |
| **Deploy** | Ansible | Installs Java/PetClinic + PostgreSQL, .NET/MVC + SQL Server, PHP/Laravel + MySQL on each VM (Linux via systemd, Windows via IIS/NSSM) |
| **Prepare** | Ansible | Enables SSH/WinRM, sysstat, firewall rules, and optional Azure Migrate Dependency Agent |
| **Assess** | Azure Migrate | You point the Azure Migrate appliance at your vCenter and discover all VMs |

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                              VMware vSphere                                  │
│                                                                              │
│  Linux Mode (deploy_mode = linux)                                            │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐                       │
│  │  VM: java-vm  │  │  VM: dotnet-vm│  │  VM: php-vm  │                      │
│  │  Ubuntu 22.04 │  │  Ubuntu 22.04 │  │  Ubuntu 22.04│                      │
│  │  Spring       │  │  ASP.NET Core │  │  Laravel     │                      │
│  │  PetClinic    │  │  MVC + Nginx  │  │  + Apache2   │                      │
│  │  (Java 17)    │  │  (.NET 6)     │  │  (PHP 8.1)   │                      │
│  │  PostgreSQL 15│  │  SQL Server   │  │  MySQL 8.0   │                      │
│  │               │  │  2022 Express │  │              │                      │
│  └──────────────┘  └──────────────┘  └──────────────┘                       │
│                                       ── OR ──                               │
│  Windows Mode (deploy_mode = windows)                                        │
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
│                    Choose ONE mode — 3 VMs per mode                          │
└──────────────────────────────────────────────────────────────────────────────┘
         │
         ▼  Azure Migrate Appliance discovers these VMs
┌──────────────────────────────────────────────────────────────────────────────┐
│  Migration Targets:                                                          │
│  Azure IaaS (VMs)           │  Azure PaaS                                    │
│  • Azure VMs                │  • App Service                                 │
│  • Managed Disks            │  • Azure SQL / Postgres / MySQL                │
│  • NSGs, VNets              │  • Azure Container Apps                        │
└──────────────────────────────────────────────────────────────────────────────┘
```

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
| **Network** | A port group with DHCP or a static IP range you can assign to 3 VMs |
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
   # Enable WinRM for Ansible connectivity
   winrm quickconfig -force
   winrm set winrm/config/service '@{AllowUnencrypted="true"}'
   winrm set winrm/config/service/auth '@{Basic="true"}'
   Enable-PSRemoting -Force

   # Configure WinRM for HTTPS (self-signed cert)
   $cert = New-SelfSignedCertificate -DnsName $env:COMPUTERNAME -CertStoreLocation Cert:\LocalMachine\My

   # Create the HTTPS listener using the cert thumbprint (run this SEPARATELY after the line above)
   $hostname = $env:COMPUTERNAME
   $thumbprint = $cert.Thumbprint
   winrm create winrm/config/Listener?Address=*+Transport=HTTPS "@{Hostname=`"$hostname`";CertificateThumbprint=`"$thumbprint`"}"

   # Open firewall for WinRM HTTPS
   New-NetFirewallRule -Name "WinRM-HTTPS" -DisplayName "WinRM HTTPS" -Protocol TCP -LocalPort 5986 -Action Allow

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
| 4. VM Sizing & IPs | Static IP + CPU/RAM/Disk per VM (3 Linux or 3 Windows) | `192.168.1.101`, 2 CPU, 4096 MB |
| 5. App & DB Config | Git repos, versions, database passwords | JDK 17, PostgreSQL password |
| 6. Azure Migrate | Install dependency agent? | Yes/No |

After confirming the summary, choose a run mode:

```
[1] Full pipeline (Terraform + Ansible + Verify)   ← recommended for first run
[2] Stop here — review config files before running  ← default
[3] Terraform only                                  ← just provision VMs
[4] Ansible only                                    ← VMs already exist, just deploy apps
[5] Destroy all VMs                                 ← clean up a failed or previous run
```

> **Re-running the wizard:** On subsequent runs, all prompts pre-fill with your previously saved values. Just press Enter to keep them, or type a new value. Passwords are always re-prompted.

**Option 1** runs everything end-to-end. Expect **~20-35 minutes** total:
- ~5 min for Terraform to create 3 VMs
- ~1 min waiting for VMs to boot
- ~15-25 min for Ansible to install all apps and databases
- ~5-10 min extra for Windows mode (SQL Server + Chocolatey downloads)

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

### Linux Mode (deploy_mode = linux)

| VM | Hostname | OS | Application | Web Server | Database | Access URL |
|----|----------|-----|------------|------------|----------|------------|
| **Java VM** | legacy-java-vm | Ubuntu 22.04 | Spring PetClinic (Java 17, Spring Boot) | Embedded Tomcat | PostgreSQL 15 | `http://<java-ip>:8080` |
| **\.NET VM** | legacy-dotnet-vm | Ubuntu 22.04 | ASP.NET Core MVC (.NET 6) | Kestrel + Nginx reverse proxy | SQL Server 2022 Express | `http://<dotnet-ip>` |
| **PHP VM** | legacy-php-vm | Ubuntu 22.04 | Laravel sample app (PHP 8.1) | Apache2 + mod_php | MySQL 8.0 | `http://<php-ip>` |

### Windows Mode (deploy_mode = windows)

| VM | Hostname | OS | Application | Web Server | Database | Access URL |
|----|----------|-----|------------|------------|----------|------------|
| **Win Java VM** | legacy-win-java-vm | Windows Server 2019 | Spring PetClinic (Java 17, Spring Boot) | NSSM service | PostgreSQL 15 | `http://<java-ip>:8080` |
| **Win .NET VM** | legacy-win-dotnet-vm | Windows Server 2019 | ASP.NET Framework Web Forms (.NET 4.5) | IIS 10 | SQL Server 2019 Express | `http://<dotnet-ip>` |
| **Win PHP VM** | legacy-win-php-vm | Windows Server 2019 | Laravel (PHP + IIS FastCGI) | IIS 10 | MySQL | `http://<php-ip>` |

Each app:
- Runs as a **systemd service** (Linux) or **Windows service / IIS site** (Windows) — auto-starts on boot
- Has its database installed **locally on the same VM** (simulates typical legacy architecture)
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
│   ├── main.tf                        # Linux + Windows VM resources + clone from template
│   ├── variables.tf                   # All configurable parameters (incl. Windows VM)
│   ├── outputs.tf                     # VM IPs output after apply
│   ├── terraform.tfvars.example       # Template — fill with your values
│   └── templates/
│       └── hosts.ini.tftpl            # Auto-generates Ansible inventory (SSH + WinRM)
│
├── ansible/                           # App deployment over SSH (Linux) / WinRM (Windows)
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
│       ├── win-java-petclinic.yml     # Windows: Java PetClinic + PostgreSQL
│       ├── win-iis-app.yml            # Windows: IIS + ASP.NET Framework + SQL Server 2019
│       ├── win-php-app.yml            # Windows: PHP Laravel + MySQL + IIS
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
| `java_vm_ip` | Static IP for Java VM (both modes) | `192.168.1.101` |
| `dotnet_vm_ip` | Static IP for .NET VM (both modes) | `192.168.1.102` |
| `php_vm_ip` | Static IP for PHP VM (both modes) | `192.168.1.103` |
| `deploy_mode` | Deployment mode: `linux` or `windows` | `linux` |
| `win_template_name` | Windows Server template name in vCenter | `windows-2019-template` |
| `win_admin_password` | Windows Administrator password | `MyP@ssw0rd` |

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

**Linux Mode:**

| VM | Discovered Apps | Discovered DBs | Dependencies |
|----|----------------|----------------|-------------|
| legacy-java-vm | Java 17, Spring Boot, Tomcat | PostgreSQL 15 | → PostgreSQL (localhost:5432) |
| legacy-dotnet-vm | .NET 6, ASP.NET Core, Nginx | SQL Server 2022 | → SQL Server (localhost:1433) |
| legacy-php-vm | PHP 8.1, Apache2, Laravel | MySQL 8.0 | → MySQL (localhost:3306) |

**Windows Mode:**

| VM | Discovered Apps | Discovered DBs | Dependencies |
|----|----------------|----------------|-------------|
| legacy-win-java-vm | Java 17, Spring Boot, NSSM | PostgreSQL 15 | → PostgreSQL (localhost:5432) |
| legacy-win-dotnet-vm | .NET 4.5, IIS 10, ASP.NET | SQL Server 2019 | → SQL Server (localhost:1433) |
| legacy-win-php-vm | PHP, IIS 10, Laravel | MySQL | → MySQL (localhost:3306) |

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
- **Failed run?** Run `bash scripts/setup-interactive.sh --destroy` to clean up, then re-run

### Resuming after Ansible failure
If Ansible fails (e.g., SSH connection timeout, missing sshpass), you can resume without re-running Terraform:

```bash
# Resume — retries only the failed hosts
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

### Quick destroy via wizard
```bash
# Fastest way — skips the wizard, goes straight to destroy
bash scripts/setup-interactive.sh --destroy
```

Or re-run the wizard and pick **option 6** at the end.

### Destroy manually (keep config)
```bash
cd terraform
terraform init       # needed if .terraform/ is missing
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
