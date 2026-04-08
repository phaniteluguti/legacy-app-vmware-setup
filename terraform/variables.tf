# --- Deployment Mode ---
variable "deploy_mode" {
  description = "Deployment mode: 'linux' or 'windows' (single VM per app), 'linux-3tier' or 'windows-3tier' (frontend + appserver + database VMs)"
  type        = string
  default     = "linux"
  validation {
    condition     = contains(["linux", "windows", "linux-3tier", "windows-3tier"], var.deploy_mode)
    error_message = "deploy_mode must be 'linux', 'windows', 'linux-3tier', or 'windows-3tier'."
  }
}

# --- vSphere Connection ---
variable "vsphere_server" {
  description = "vCenter Server FQDN or IP"
  type        = string
}

variable "vsphere_user" {
  description = "vCenter admin username"
  type        = string
}

variable "vsphere_password" {
  description = "vCenter admin password"
  type        = string
  sensitive   = true
}

variable "vsphere_allow_unverified_ssl" {
  description = "Allow unverified SSL certs for vCenter"
  type        = bool
  default     = true
}

# --- vSphere Infrastructure ---
variable "vsphere_datacenter" {
  description = "vSphere datacenter name"
  type        = string
}

variable "vsphere_cluster" {
  description = "vSphere compute cluster name"
  type        = string
}

variable "vsphere_datastore" {
  description = "vSphere datastore name"
  type        = string
}

variable "vsphere_network" {
  description = "vSphere port group / network name"
  type        = string
}

variable "vsphere_folder" {
  description = "VM folder in vSphere (optional)"
  type        = string
  default     = ""
}

variable "vm_template_name" {
  description = "Name of the Ubuntu 22.04 VM template in vSphere"
  type        = string
}

# --- VM Networking ---
variable "vm_domain" {
  description = "Domain for VM hostname"
  type        = string
  default     = "local"
}

variable "vm_gateway" {
  description = "Default gateway IP"
  type        = string
}

variable "vm_netmask" {
  description = "Subnet mask bits (e.g. 24)"
  type        = number
  default     = 24
}

variable "vm_dns_servers" {
  description = "DNS server IPs"
  type        = list(string)
  default     = ["8.8.8.8", "8.8.4.4"]
}

variable "vm_ssh_user" {
  description = "SSH user configured in the VM template"
  type        = string
  default     = "ubuntu"
}

variable "vm_ssh_auth_method" {
  description = "SSH auth method: 'key' or 'password'"
  type        = string
  default     = "key"
}

variable "vm_ssh_private_key_path" {
  description = "Path to SSH private key for VM access (used when auth_method = key)"
  type        = string
  default     = "~/.ssh/id_rsa"
}

variable "vm_ssh_password" {
  description = "SSH password for VM access (used when auth_method = password)"
  type        = string
  default     = ""
  sensitive   = true
}

# --- Java VM ---
variable "java_vm_ip" {
  description = "Static IP for the Java VM"
  type        = string
  default     = ""
}

variable "java_vm_cpus" {
  type    = number
  default = 2
}

variable "java_vm_memory" {
  description = "Memory in MB"
  type        = number
  default     = 4096
}

variable "java_vm_disk" {
  description = "Disk size in GB"
  type        = number
  default     = 40
}

# --- .NET VM ---
variable "dotnet_vm_ip" {
  description = "Static IP for the .NET VM"
  type        = string
  default     = ""
}

variable "dotnet_vm_cpus" {
  type    = number
  default = 2
}

variable "dotnet_vm_memory" {
  type    = number
  default = 4096
}

variable "dotnet_vm_disk" {
  type    = number
  default = 40
}

# --- PHP VM ---
variable "php_vm_ip" {
  description = "Static IP for the PHP VM"
  type        = string
  default     = ""
}

variable "php_vm_cpus" {
  type    = number
  default = 2
}

variable "php_vm_memory" {
  type    = number
  default = 2048
}

variable "php_vm_disk" {
  type    = number
  default = 30
}

# --- Windows VM Settings ---
variable "win_template_name" {
  description = "Name of the Windows Server 2019 VM template in vSphere"
  type        = string
  default     = "windows-2019-template"
}

variable "win_admin_password" {
  description = "Windows local Administrator password"
  type        = string
  default     = ""
  sensitive   = true
}

# =============================================================================
# 3-Tier Mode — Linux VMs (9 VMs: 3 apps × frontend + appserver + database)
# =============================================================================
variable "java_fe_ip" {
  description = "Static IP for Java frontend VM (Nginx + Angular)"
  type        = string
  default     = "10.1.2.20"
}
variable "java_app_ip" {
  description = "Static IP for Java app server VM (Spring Boot REST)"
  type        = string
  default     = "10.1.2.21"
}
variable "java_db_ip" {
  description = "Static IP for Java database VM (PostgreSQL)"
  type        = string
  default     = "10.1.2.22"
}
variable "dotnet_fe_ip" {
  description = "Static IP for .NET frontend VM (Nginx + Blazor)"
  type        = string
  default     = "10.1.2.23"
}
variable "dotnet_app_ip" {
  description = "Static IP for .NET app server VM (ASP.NET Core)"
  type        = string
  default     = "10.1.2.24"
}
variable "dotnet_db_ip" {
  description = "Static IP for .NET database VM (SQL Server)"
  type        = string
  default     = "10.1.2.25"
}
variable "php_fe_ip" {
  description = "Static IP for PHP frontend VM (Nginx + Vue.js)"
  type        = string
  default     = "10.1.2.26"
}
variable "php_app_ip" {
  description = "Static IP for PHP app server VM (Laravel API)"
  type        = string
  default     = "10.1.2.27"
}
variable "php_db_ip" {
  description = "Static IP for PHP database VM (MySQL)"
  type        = string
  default     = "10.1.2.28"
}

# =============================================================================
# 3-Tier Mode — Windows VMs (9 VMs)
# =============================================================================
variable "win_java_fe_ip" {
  description = "Static IP for Windows Java frontend VM"
  type        = string
  default     = "10.1.2.30"
}
variable "win_java_app_ip" {
  description = "Static IP for Windows Java app server VM"
  type        = string
  default     = "10.1.2.31"
}
variable "win_java_db_ip" {
  description = "Static IP for Windows Java database VM"
  type        = string
  default     = "10.1.2.32"
}
variable "win_dotnet_fe_ip" {
  description = "Static IP for Windows .NET frontend VM"
  type        = string
  default     = "10.1.2.33"
}
variable "win_dotnet_app_ip" {
  description = "Static IP for Windows .NET app server VM"
  type        = string
  default     = "10.1.2.34"
}
variable "win_dotnet_db_ip" {
  description = "Static IP for Windows .NET database VM"
  type        = string
  default     = "10.1.2.35"
}
variable "win_php_fe_ip" {
  description = "Static IP for Windows PHP frontend VM"
  type        = string
  default     = "10.1.2.36"
}
variable "win_php_app_ip" {
  description = "Static IP for Windows PHP app server VM"
  type        = string
  default     = "10.1.2.37"
}
variable "win_php_db_ip" {
  description = "Static IP for Windows PHP database VM"
  type        = string
  default     = "10.1.2.38"
}
