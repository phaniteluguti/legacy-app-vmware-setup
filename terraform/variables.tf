# --- Deployment Mode ---
variable "deploy_mode" {
  description = "Deployment mode: 'linux' for 3 Linux VMs or 'windows' for 3 Windows VMs"
  type        = string
  default     = "linux"
  validation {
    condition     = contains(["linux", "windows"], var.deploy_mode)
    error_message = "deploy_mode must be 'linux' or 'windows'."
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
