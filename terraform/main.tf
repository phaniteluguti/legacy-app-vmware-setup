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
  count         = var.deploy_mode == "linux" ? 1 : 0
  name          = var.vm_template_name
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_virtual_machine" "windows_template" {
  count         = var.deploy_mode == "windows" ? 1 : 0
  name          = var.win_template_name
  datacenter_id = data.vsphere_datacenter.dc.id
}

# --- Local variables ---
locals {
  vms = var.deploy_mode == "linux" ? {
    java-vm = {
      name   = "legacy-java-vm"
      cpus   = var.java_vm_cpus
      memory = var.java_vm_memory
      disk   = var.java_vm_disk
      ip     = var.java_vm_ip
    }
    dotnet-vm = {
      name   = "legacy-dotnet-vm"
      cpus   = var.dotnet_vm_cpus
      memory = var.dotnet_vm_memory
      disk   = var.dotnet_vm_disk
      ip     = var.dotnet_vm_ip
    }
    php-vm = {
      name   = "legacy-php-vm"
      cpus   = var.php_vm_cpus
      memory = var.php_vm_memory
      disk   = var.php_vm_disk
      ip     = var.php_vm_ip
    }
  } : {}

  win_vms = var.deploy_mode == "windows" ? {
    win-java-vm = {
      name          = "legacy-win-java-vm"
      computer_name = "WIN-JAVA"
      cpus   = var.java_vm_cpus
      memory = var.java_vm_memory
      disk   = var.java_vm_disk
      ip     = var.java_vm_ip
    }
    win-dotnet-vm = {
      name          = "legacy-win-dotnet-vm"
      computer_name = "WIN-DOTNET"
      cpus   = var.dotnet_vm_cpus
      memory = var.dotnet_vm_memory
      disk   = var.dotnet_vm_disk
      ip     = var.dotnet_vm_ip
    }
    win-php-vm = {
      name          = "legacy-win-php-vm"
      computer_name = "WIN-PHP"
      cpus   = var.php_vm_cpus
      memory = var.php_vm_memory
      disk   = var.php_vm_disk
      ip     = var.php_vm_ip
    }
  } : {}
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

# --- Generate Ansible inventory ---
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/templates/hosts.ini.tftpl", {
    deploy_mode   = var.deploy_mode
    java_ip       = var.deploy_mode == "linux" ? vsphere_virtual_machine.vm["java-vm"].default_ip_address : ""
    dotnet_ip     = var.deploy_mode == "linux" ? vsphere_virtual_machine.vm["dotnet-vm"].default_ip_address : ""
    php_ip        = var.deploy_mode == "linux" ? vsphere_virtual_machine.vm["php-vm"].default_ip_address : ""
    ssh_user      = var.vm_ssh_user
    ssh_auth_line = var.vm_ssh_auth_method == "password" ? "ansible_ssh_pass=${var.vm_ssh_password} ansible_become_pass=${var.vm_ssh_password} ansible_ssh_common_args='-o StrictHostKeyChecking=no'" : "ansible_ssh_private_key_file=${var.vm_ssh_private_key_path}"
    win_java_ip   = var.deploy_mode == "windows" ? vsphere_virtual_machine.win_vm["win-java-vm"].default_ip_address : ""
    win_dotnet_ip = var.deploy_mode == "windows" ? vsphere_virtual_machine.win_vm["win-dotnet-vm"].default_ip_address : ""
    win_php_ip    = var.deploy_mode == "windows" ? vsphere_virtual_machine.win_vm["win-php-vm"].default_ip_address : ""
    win_password  = var.win_admin_password
  })
  filename = "${path.module}/../ansible/inventory/hosts.ini"
}
