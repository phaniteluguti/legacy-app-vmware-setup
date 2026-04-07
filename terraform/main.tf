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
  name          = var.vm_template_name
  datacenter_id = data.vsphere_datacenter.dc.id
}

# --- Local variables ---
locals {
  vms = {
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
  }
}

# --- Virtual Machines ---
resource "vsphere_virtual_machine" "vm" {
  for_each = local.vms

  name             = each.value.name
  resource_pool_id = data.vsphere_compute_cluster.cluster.resource_pool_id
  datastore_id     = data.vsphere_datastore.datastore.id
  folder           = var.vsphere_folder

  num_cpus = each.value.cpus
  memory   = each.value.memory

  guest_id = data.vsphere_virtual_machine.template.guest_id

  network_interface {
    network_id   = data.vsphere_network.network.id
    adapter_type = data.vsphere_virtual_machine.template.network_interface_types[0]
  }

  disk {
    label            = "disk0"
    size             = each.value.disk
    thin_provisioned = true
  }

  clone {
    template_uuid = data.vsphere_virtual_machine.template.id

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

  tags = [
    "legacy-app",
    "azure-migrate-target"
  ]

  lifecycle {
    ignore_changes = [
      annotation,
    ]
  }
}

# --- Generate Ansible inventory ---
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/templates/hosts.ini.tftpl", {
    java_ip   = vsphere_virtual_machine.vm["java-vm"].default_ip_address
    dotnet_ip = vsphere_virtual_machine.vm["dotnet-vm"].default_ip_address
    php_ip    = vsphere_virtual_machine.vm["php-vm"].default_ip_address
    ssh_user  = var.vm_ssh_user
    ssh_key   = var.vm_ssh_private_key_path
  })
  filename = "${path.module}/../ansible/inventory/hosts.ini"
}
