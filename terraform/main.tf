terraform {
  required_version = ">= 1.5.0"
  required_providers {
    vsphere = {
      source  = "hashicorp/vsphere"
      version = "~> 2.6"
    }
  }
}

# --- Provider ---
provider "vsphere" {
  user                 = var.vsphere_user
  password             = var.vsphere_password
  vsphere_server       = var.vsphere_server
  allow_unverified_ssl = var.vsphere_allow_unverified_ssl
}

# --- Data Sources ---
data "vsphere_datacenter" "dc" {
  name = var.vsphere_datacenter
}

data "vsphere_compute_cluster" "cluster" {
  name          = var.vsphere_cluster
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_datastore" "datastore" {
  name          = var.vsphere_datastore
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_network" "network" {
  name          = var.vsphere_network
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_virtual_machine" "template" {
  count         = contains(["linux", "linux-3tier"], var.deploy_mode) ? 1 : 0
  name          = var.vm_template_name
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_virtual_machine" "windows_template" {
  count         = contains(["windows", "windows-3tier"], var.deploy_mode) ? 1 : 0
  name          = var.win_template_name
  datacenter_id = data.vsphere_datacenter.dc.id
}

# --- Local variables ---
locals {
  vms = var.deploy_mode == "linux" ? merge(
    var.deploy_java ? {
      java-vm = {
        name   = "legacy-java-vm"
        cpus   = var.java_vm_cpus
        memory = var.java_vm_memory
        disk   = var.java_vm_disk
        ip     = var.java_vm_ip
      }
    } : {},
    var.deploy_dotnet ? {
      dotnet-vm = {
        name   = "legacy-dotnet-vm"
        cpus   = var.dotnet_vm_cpus
        memory = var.dotnet_vm_memory
        disk   = var.dotnet_vm_disk
        ip     = var.dotnet_vm_ip
      }
    } : {},
    var.deploy_php ? {
      php-vm = {
        name   = "legacy-php-vm"
        cpus   = var.php_vm_cpus
        memory = var.php_vm_memory
        disk   = var.php_vm_disk
        ip     = var.php_vm_ip
      }
    } : {}
  ) : {}

  win_vms = var.deploy_mode == "windows" ? merge(
    var.deploy_java ? {
      win-java-vm = {
        name          = "legacy-win-java-vm"
        computer_name = "WIN-JAVA"
        cpus   = var.java_vm_cpus
        memory = var.java_vm_memory
        disk   = var.java_vm_disk
        ip     = var.java_vm_ip
      }
    } : {},
    var.deploy_dotnet ? {
      win-dotnet-vm = {
        name          = "legacy-win-dotnet-vm"
        computer_name = "WIN-DOTNET"
        cpus   = var.dotnet_vm_cpus
        memory = var.dotnet_vm_memory
        disk   = var.dotnet_vm_disk
        ip     = var.dotnet_vm_ip
      }
    } : {},
    var.deploy_php ? {
      win-php-vm = {
        name          = "legacy-win-php-vm"
        computer_name = "WIN-PHP"
        cpus   = var.php_vm_cpus
        memory = var.php_vm_memory
        disk   = var.php_vm_disk
        ip     = var.php_vm_ip
      }
    } : {}
  ) : {}

  # --- 3-Tier Linux VMs (up to 9 VMs) ---
  vms_3tier = var.deploy_mode == "linux-3tier" ? merge(
    var.deploy_java ? {
      java-fe = {
        name   = "3t-java-fe"
        cpus   = 1
        memory = 2048
        disk   = 20
        ip     = var.java_fe_ip
      }
      java-app = {
        name   = "3t-java-app"
        cpus   = 2
        memory = 4096
        disk   = 40
        ip     = var.java_app_ip
      }
      java-db = {
        name   = "3t-java-db"
        cpus   = 2
        memory = 4096
        disk   = 60
        ip     = var.java_db_ip
      }
    } : {},
    var.deploy_dotnet ? {
      dotnet-fe = {
        name   = "3t-dotnet-fe"
        cpus   = 1
        memory = 2048
        disk   = 20
        ip     = var.dotnet_fe_ip
      }
      dotnet-app = {
        name   = "3t-dotnet-app"
        cpus   = 2
        memory = 4096
        disk   = 40
        ip     = var.dotnet_app_ip
      }
      dotnet-db = {
        name   = "3t-dotnet-db"
        cpus   = 2
        memory = 4096
        disk   = 60
        ip     = var.dotnet_db_ip
      }
    } : {},
    var.deploy_php ? {
      php-fe = {
        name   = "3t-php-fe"
        cpus   = 1
        memory = 2048
        disk   = 20
        ip     = var.php_fe_ip
      }
      php-app = {
        name   = "3t-php-app"
        cpus   = 2
        memory = 4096
        disk   = 40
        ip     = var.php_app_ip
      }
      php-db = {
        name   = "3t-php-db"
        cpus   = 2
        memory = 4096
        disk   = 60
        ip     = var.php_db_ip
      }
    } : {}
  ) : {}

  # --- 3-Tier Windows VMs (up to 9 VMs) ---
  win_vms_3tier = var.deploy_mode == "windows-3tier" ? merge(
    var.deploy_java ? {
      win-java-fe = {
        name          = "3t-win-java-fe"
        computer_name = "WIN-JAVA-FE"
        cpus   = 1
        memory = 2048
        disk   = 20
        ip     = var.win_java_fe_ip
      }
      win-java-app = {
        name          = "3t-win-java-app"
        computer_name = "WIN-JAVA-APP"
        cpus   = 2
        memory = 4096
        disk   = 40
        ip     = var.win_java_app_ip
      }
      win-java-db = {
        name          = "3t-win-java-db"
        computer_name = "WIN-JAVA-DB"
        cpus   = 2
        memory = 4096
        disk   = 60
        ip     = var.win_java_db_ip
      }
    } : {},
    var.deploy_dotnet ? {
      win-dotnet-fe = {
        name          = "3t-win-dotnet-fe"
        computer_name = "WIN-NET-FE"
        cpus   = 1
        memory = 2048
        disk   = 20
        ip     = var.win_dotnet_fe_ip
      }
      win-dotnet-app = {
        name          = "3t-win-dotnet-app"
        computer_name = "WIN-NET-APP"
        cpus   = 2
        memory = 4096
        disk   = 40
        ip     = var.win_dotnet_app_ip
      }
      win-dotnet-db = {
        name          = "3t-win-dotnet-db"
        computer_name = "WIN-NET-DB"
        cpus   = 2
        memory = 4096
        disk   = 60
        ip     = var.win_dotnet_db_ip
      }
    } : {},
    var.deploy_php ? {
      win-php-fe = {
        name          = "3t-win-php-fe"
        computer_name = "WIN-PHP-FE"
        cpus   = 1
        memory = 2048
        disk   = 20
        ip     = var.win_php_fe_ip
      }
      win-php-app = {
        name          = "3t-win-php-app"
        computer_name = "WIN-PHP-APP"
        cpus   = 2
        memory = 4096
        disk   = 40
        ip     = var.win_php_app_ip
      }
      win-php-db = {
        name          = "3t-win-php-db"
        computer_name = "WIN-PHP-DB"
        cpus   = 2
        memory = 4096
        disk   = 60
        ip     = var.win_php_db_ip
      }
    } : {}
  ) : {}
}

# --- Linux Virtual Machines ---
resource "vsphere_virtual_machine" "vm" {
  for_each = local.vms

  name             = each.value.name
  resource_pool_id = data.vsphere_compute_cluster.cluster.resource_pool_id
  datastore_id     = data.vsphere_datastore.datastore.id
  folder           = var.vsphere_folder

  num_cpus = each.value.cpus
  memory   = each.value.memory

  guest_id = data.vsphere_virtual_machine.template[0].guest_id

  network_interface {
    network_id   = data.vsphere_network.network.id
    adapter_type = data.vsphere_virtual_machine.template[0].network_interface_types[0]
  }

  disk {
    label            = "disk0"
    size             = each.value.disk
    thin_provisioned = true
  }

  clone {
    template_uuid = data.vsphere_virtual_machine.template[0].id

    customize {
      linux_options {
        host_name = each.value.name
        domain    = var.vm_domain
      }

      network_interface {
        ipv4_address = each.value.ip
        ipv4_netmask = var.vm_netmask
      }

      ipv4_gateway    = var.vm_gateway
      dns_server_list = var.vm_dns_servers
    }
  }

  lifecycle {
    ignore_changes = [
      annotation,
    ]
  }
}

# --- Windows Virtual Machines ---
resource "vsphere_virtual_machine" "win_vm" {
  for_each = local.win_vms

  name             = each.value.name
  resource_pool_id = data.vsphere_compute_cluster.cluster.resource_pool_id
  datastore_id     = data.vsphere_datastore.datastore.id
  folder           = var.vsphere_folder

  num_cpus = each.value.cpus
  memory   = each.value.memory

  guest_id = data.vsphere_virtual_machine.windows_template[0].guest_id

  wait_for_guest_net_timeout  = 15
  wait_for_guest_ip_timeout   = 15

  network_interface {
    network_id   = data.vsphere_network.network.id
    adapter_type = data.vsphere_virtual_machine.windows_template[0].network_interface_types[0]
  }

  disk {
    label            = "disk0"
    size             = each.value.disk
    thin_provisioned = true
  }

  clone {
    template_uuid = data.vsphere_virtual_machine.windows_template[0].id

    customize {
      windows_options {
        computer_name  = each.value.computer_name
        admin_password = var.win_admin_password
        run_once_command_list = [
          "cmd.exe /c winrm quickconfig -force",
          "cmd.exe /c winrm set winrm/config/service @{AllowUnencrypted=\"true\"}",
          "cmd.exe /c winrm set winrm/config/service/auth @{Basic=\"true\"}",
          "powershell.exe -Command Enable-PSRemoting -Force",
          "powershell.exe -Command New-NetFirewallRule -Name WinRM-HTTP -DisplayName 'WinRM HTTP' -Protocol TCP -LocalPort 5985 -Action Allow",
        ]
      }

      network_interface {
        ipv4_address = each.value.ip
        ipv4_netmask = var.vm_netmask
      }

      ipv4_gateway    = var.vm_gateway
      dns_server_list = var.vm_dns_servers
    }
  }

  lifecycle {
    ignore_changes = [
      annotation,
    ]
  }
}

# --- 3-Tier Linux Virtual Machines ---
resource "vsphere_virtual_machine" "vm_3tier" {
  for_each = local.vms_3tier

  name             = each.value.name
  resource_pool_id = data.vsphere_compute_cluster.cluster.resource_pool_id
  datastore_id     = data.vsphere_datastore.datastore.id
  folder           = var.vsphere_folder

  num_cpus = each.value.cpus
  memory   = each.value.memory

  guest_id = data.vsphere_virtual_machine.template[0].guest_id

  network_interface {
    network_id   = data.vsphere_network.network.id
    adapter_type = data.vsphere_virtual_machine.template[0].network_interface_types[0]
  }

  disk {
    label            = "disk0"
    size             = each.value.disk
    thin_provisioned = true
  }

  clone {
    template_uuid = data.vsphere_virtual_machine.template[0].id

    customize {
      linux_options {
        host_name = each.value.name
        domain    = var.vm_domain
      }

      network_interface {
        ipv4_address = each.value.ip
        ipv4_netmask = var.vm_netmask
      }

      ipv4_gateway    = var.vm_gateway
      dns_server_list = var.vm_dns_servers
    }
  }

  lifecycle {
    ignore_changes = [annotation]
  }
}

# --- 3-Tier Windows Virtual Machines ---
resource "vsphere_virtual_machine" "win_vm_3tier" {
  for_each = local.win_vms_3tier

  name             = each.value.name
  resource_pool_id = data.vsphere_compute_cluster.cluster.resource_pool_id
  datastore_id     = data.vsphere_datastore.datastore.id
  folder           = var.vsphere_folder

  num_cpus = each.value.cpus
  memory   = each.value.memory

  guest_id = data.vsphere_virtual_machine.windows_template[0].guest_id

  wait_for_guest_net_timeout = 15
  wait_for_guest_ip_timeout  = 15

  network_interface {
    network_id   = data.vsphere_network.network.id
    adapter_type = data.vsphere_virtual_machine.windows_template[0].network_interface_types[0]
  }

  disk {
    label            = "disk0"
    size             = each.value.disk
    thin_provisioned = true
  }

  clone {
    template_uuid = data.vsphere_virtual_machine.windows_template[0].id

    customize {
      windows_options {
        computer_name  = each.value.computer_name
        admin_password = var.win_admin_password
        run_once_command_list = [
          "cmd.exe /c winrm quickconfig -force",
          "cmd.exe /c winrm set winrm/config/service @{AllowUnencrypted=\"true\"}",
          "cmd.exe /c winrm set winrm/config/service/auth @{Basic=\"true\"}",
          "powershell.exe -Command Enable-PSRemoting -Force",
          "powershell.exe -Command New-NetFirewallRule -Name WinRM-HTTP -DisplayName 'WinRM HTTP' -Protocol TCP -LocalPort 5985 -Action Allow",
        ]
      }

      network_interface {
        ipv4_address = each.value.ip
        ipv4_netmask = var.vm_netmask
      }

      ipv4_gateway    = var.vm_gateway
      dns_server_list = var.vm_dns_servers
    }
  }

  lifecycle {
    ignore_changes = [annotation]
  }
}

# --- Generate Ansible inventory ---
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/templates/hosts.ini.tftpl", {
    deploy_mode   = var.deploy_mode
    deploy_java   = var.deploy_java
    deploy_dotnet = var.deploy_dotnet
    deploy_php    = var.deploy_php
    java_ip       = var.deploy_mode == "linux" && var.deploy_java ? vsphere_virtual_machine.vm["java-vm"].default_ip_address : ""
    dotnet_ip     = var.deploy_mode == "linux" && var.deploy_dotnet ? vsphere_virtual_machine.vm["dotnet-vm"].default_ip_address : ""
    php_ip        = var.deploy_mode == "linux" && var.deploy_php ? vsphere_virtual_machine.vm["php-vm"].default_ip_address : ""
    ssh_user      = var.vm_ssh_user
    ssh_auth_line = var.vm_ssh_auth_method == "password" ? "ansible_ssh_pass=${var.vm_ssh_password} ansible_become_pass=${var.vm_ssh_password} ansible_ssh_common_args='-o StrictHostKeyChecking=no'" : "ansible_ssh_private_key_file=${var.vm_ssh_private_key_path}"
    win_java_ip   = var.deploy_mode == "windows" && var.deploy_java ? vsphere_virtual_machine.win_vm["win-java-vm"].default_ip_address : ""
    win_dotnet_ip = var.deploy_mode == "windows" && var.deploy_dotnet ? vsphere_virtual_machine.win_vm["win-dotnet-vm"].default_ip_address : ""
    win_php_ip    = var.deploy_mode == "windows" && var.deploy_php ? vsphere_virtual_machine.win_vm["win-php-vm"].default_ip_address : ""
    win_password  = var.win_admin_password
    # 3-tier Linux IPs
    java_fe_ip    = var.deploy_mode == "linux-3tier" && var.deploy_java ? vsphere_virtual_machine.vm_3tier["java-fe"].default_ip_address : ""
    java_app_ip   = var.deploy_mode == "linux-3tier" && var.deploy_java ? vsphere_virtual_machine.vm_3tier["java-app"].default_ip_address : ""
    java_db_ip    = var.deploy_mode == "linux-3tier" && var.deploy_java ? vsphere_virtual_machine.vm_3tier["java-db"].default_ip_address : ""
    dotnet_fe_ip  = var.deploy_mode == "linux-3tier" && var.deploy_dotnet ? vsphere_virtual_machine.vm_3tier["dotnet-fe"].default_ip_address : ""
    dotnet_app_ip = var.deploy_mode == "linux-3tier" && var.deploy_dotnet ? vsphere_virtual_machine.vm_3tier["dotnet-app"].default_ip_address : ""
    dotnet_db_ip  = var.deploy_mode == "linux-3tier" && var.deploy_dotnet ? vsphere_virtual_machine.vm_3tier["dotnet-db"].default_ip_address : ""
    php_fe_ip     = var.deploy_mode == "linux-3tier" && var.deploy_php ? vsphere_virtual_machine.vm_3tier["php-fe"].default_ip_address : ""
    php_app_ip    = var.deploy_mode == "linux-3tier" && var.deploy_php ? vsphere_virtual_machine.vm_3tier["php-app"].default_ip_address : ""
    php_db_ip     = var.deploy_mode == "linux-3tier" && var.deploy_php ? vsphere_virtual_machine.vm_3tier["php-db"].default_ip_address : ""
    # 3-tier Windows IPs
    win_java_fe_ip    = var.deploy_mode == "windows-3tier" && var.deploy_java ? vsphere_virtual_machine.win_vm_3tier["win-java-fe"].default_ip_address : ""
    win_java_app_ip   = var.deploy_mode == "windows-3tier" && var.deploy_java ? vsphere_virtual_machine.win_vm_3tier["win-java-app"].default_ip_address : ""
    win_java_db_ip    = var.deploy_mode == "windows-3tier" && var.deploy_java ? vsphere_virtual_machine.win_vm_3tier["win-java-db"].default_ip_address : ""
    win_dotnet_fe_ip  = var.deploy_mode == "windows-3tier" && var.deploy_dotnet ? vsphere_virtual_machine.win_vm_3tier["win-dotnet-fe"].default_ip_address : ""
    win_dotnet_app_ip = var.deploy_mode == "windows-3tier" && var.deploy_dotnet ? vsphere_virtual_machine.win_vm_3tier["win-dotnet-app"].default_ip_address : ""
    win_dotnet_db_ip  = var.deploy_mode == "windows-3tier" && var.deploy_dotnet ? vsphere_virtual_machine.win_vm_3tier["win-dotnet-db"].default_ip_address : ""
    win_php_fe_ip     = var.deploy_mode == "windows-3tier" && var.deploy_php ? vsphere_virtual_machine.win_vm_3tier["win-php-fe"].default_ip_address : ""
    win_php_app_ip    = var.deploy_mode == "windows-3tier" && var.deploy_php ? vsphere_virtual_machine.win_vm_3tier["win-php-app"].default_ip_address : ""
    win_php_db_ip     = var.deploy_mode == "windows-3tier" && var.deploy_php ? vsphere_virtual_machine.win_vm_3tier["win-php-db"].default_ip_address : ""
  })
  filename = "${path.module}/../ansible/inventory/hosts.ini"
}
