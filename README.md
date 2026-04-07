# VMware Legacy App Lab — Azure Migrate Assessment Setup

Automated deployment of legacy applications (.NET, Java, PHP) on VMware Ubuntu VMs for Azure Migrate assessment simulations.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     VMware vSphere                          │
│                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │  VM: java-vm  │  │  VM: dotnet-vm│  │  VM: php-vm  │      │
│  │  Ubuntu 22.04 │  │  Ubuntu 22.04 │  │  Ubuntu 22.04│      │
│  │               │  │               │  │              │      │
│  │  App: Spring  │  │  App: ASP.NET │  │  App: PHP    │      │
│  │  PetClinic    │  │  Core MVC     │  │  Laravel     │      │
│  │  (Java 17)    │  │  (.NET 6)     │  │  (PHP 8.1)   │      │
│  │               │  │               │  │              │      │
│  │  DB: Postgres │  │  DB: SQL Srv  │  │  DB: MySQL   │      │
│  │  15           │  │  2022 Express │  │  8.0         │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
│                                                             │
│  ┌──────────────────────────────────────────────────┐       │
│  │  Azure Migrate Appliance VM (optional)           │       │
│  │  Discovers & assesses all the above VMs           │       │
│  └──────────────────────────────────────────────────┘       │
└─────────────────────────────────────────────────────────────┘
         │
         ▼  Azure Migrate Assessment
┌─────────────────────────────────────────────────────────────┐
│  Azure IaaS (lift-and-shift)  OR  Azure PaaS               │
│  • Azure VMs                   • App Service                │
│  • Managed Disks               • Azure SQL / Postgres / MySQL│
│  • NSGs, VNets                 • Azure Container Apps       │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

- VMware vSphere 6.7+ / ESXi with access credentials
- Ubuntu 22.04 VM template in vSphere (or ISO for packer)
- Terraform >= 1.5
- Ansible >= 2.14
- SSH key pair for VM access
- Network connectivity from control node to VMware and VMs

## Quick Start

```bash
# 1. Clone & configure
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# Edit terraform.tfvars with your vSphere credentials & settings

cp ansible/group_vars/all.yml.example ansible/group_vars/all.yml
# Edit all.yml with desired passwords and app config

# 2. Provision VMs on vSphere
cd terraform
terraform init
terraform apply

# 3. Deploy apps via Ansible
cd ../ansible
ansible-playbook -i inventory/hosts.ini site.yml

# 4. (Optional) Prepare VMs for Azure Migrate discovery
ansible-playbook -i inventory/hosts.ini playbooks/azure-migrate-prep.yml
```

## Directory Structure

```
├── terraform/              # vSphere VM provisioning
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── terraform.tfvars.example
├── ansible/
│   ├── inventory/
│   │   └── hosts.ini
│   ├── group_vars/
│   │   └── all.yml.example
│   ├── playbooks/
│   │   ├── java-petclinic.yml    # Java + PostgreSQL
│   │   ├── dotnet-app.yml        # .NET + SQL Server
│   │   ├── php-app.yml           # PHP + MySQL
│   │   └── azure-migrate-prep.yml
│   ├── roles/               # (optional, for complex setups)
│   └── site.yml             # Master playbook
└── scripts/
    └── deploy-all.sh        # One-click orchestration
```

## What Gets Deployed

| VM | Application | Web Server | Database | Port |
|----|------------|------------|----------|------|
| java-vm | Spring PetClinic (Java 17, Spring Boot 2.x) | Embedded Tomcat | PostgreSQL 15 | 8080 |
| dotnet-vm | ASP.NET Core MVC Sample (.NET 6) | Kestrel + Nginx reverse proxy | SQL Server 2022 Express | 80 |
| php-vm | Laravel Sample App (PHP 8.1) | Apache2 | MySQL 8.0 | 80 |

## Azure Migrate Assessment

After deployment, the VMs are ready for Azure Migrate discovery:
- SSH enabled for agentless discovery
- Required ports open (SSH 22, WMI, app ports)
- Performance counters enabled for sizing recommendations
- Apps configured as systemd services for dependency mapping
