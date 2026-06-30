output "vm_ips" {
  description = "IP addresses of all provisioned VMs"
  value = merge(
    { for k, vm in vsphere_virtual_machine.vm : k => vm.default_ip_address },
    { for k, vm in vsphere_virtual_machine.win_vm : k => vm.default_ip_address },
    { for k, vm in vsphere_virtual_machine.vm_3tier : k => vm.default_ip_address },
    { for k, vm in vsphere_virtual_machine.win_vm_3tier : k => vm.default_ip_address }
  )
}

output "linux_1tier_ips" {
  description = "Linux 1-tier VM IPs"
  value       = { for k, vm in vsphere_virtual_machine.vm : k => vm.default_ip_address }
}

output "windows_1tier_ips" {
  description = "Windows 1-tier VM IPs"
  value       = { for k, vm in vsphere_virtual_machine.win_vm : k => vm.default_ip_address }
}

output "linux_3tier_ips" {
  description = "Linux 3-tier VM IPs"
  value       = { for k, vm in vsphere_virtual_machine.vm_3tier : k => vm.default_ip_address }
}

output "windows_3tier_ips" {
  description = "Windows 3-tier VM IPs"
  value       = { for k, vm in vsphere_virtual_machine.win_vm_3tier : k => vm.default_ip_address }
}

# --- Per-App Convenience Outputs (Linux 1-tier) ---
output "java_vm_ip" {
  value = try(vsphere_virtual_machine.vm["java-vm"].default_ip_address, "")
}
output "dotnet_vm_ip" {
  value = try(vsphere_virtual_machine.vm["dotnet-vm"].default_ip_address, "")
}
output "php_vm_ip" {
  value = try(vsphere_virtual_machine.vm["php-vm"].default_ip_address, "")
}

# --- Per-App Convenience Outputs (Windows 1-tier) ---
output "win_java_vm_ip" {
  value = try(vsphere_virtual_machine.win_vm["win-java-vm"].default_ip_address, "")
}
output "win_dotnet_vm_ip" {
  value = try(vsphere_virtual_machine.win_vm["win-dotnet-vm"].default_ip_address, "")
}
output "win_php_vm_ip" {
  value = try(vsphere_virtual_machine.win_vm["win-php-vm"].default_ip_address, "")
}

# --- Per-App Convenience Outputs (Linux 3-tier) ---
output "java_3tier_ips" {
  value = {
    frontend  = try(vsphere_virtual_machine.vm_3tier["java-fe"].default_ip_address, "")
    appserver = try(vsphere_virtual_machine.vm_3tier["java-app"].default_ip_address, "")
    database  = try(vsphere_virtual_machine.vm_3tier["java-db"].default_ip_address, "")
  }
}
output "dotnet_3tier_ips" {
  value = {
    frontend  = try(vsphere_virtual_machine.vm_3tier["dotnet-fe"].default_ip_address, "")
    appserver = try(vsphere_virtual_machine.vm_3tier["dotnet-app"].default_ip_address, "")
    database  = try(vsphere_virtual_machine.vm_3tier["dotnet-db"].default_ip_address, "")
  }
}
output "php_3tier_ips" {
  value = {
    frontend  = try(vsphere_virtual_machine.vm_3tier["php-fe"].default_ip_address, "")
    appserver = try(vsphere_virtual_machine.vm_3tier["php-app"].default_ip_address, "")
    database  = try(vsphere_virtual_machine.vm_3tier["php-db"].default_ip_address, "")
  }
}
output "cln_3tier_ips" {
  value = {
    frontend  = try(vsphere_virtual_machine.vm_3tier["cln-fe"].default_ip_address, "")
    appserver = try(vsphere_virtual_machine.vm_3tier["cln-app"].default_ip_address, "")
    database  = try(vsphere_virtual_machine.vm_3tier["cln-db"].default_ip_address, "")
  }
}

# --- Per-App Convenience Outputs (Windows 3-tier) ---
output "win_java_3tier_ips" {
  value = {
    frontend  = try(vsphere_virtual_machine.win_vm_3tier["win-java-fe"].default_ip_address, "")
    appserver = try(vsphere_virtual_machine.win_vm_3tier["win-java-app"].default_ip_address, "")
    database  = try(vsphere_virtual_machine.win_vm_3tier["win-java-db"].default_ip_address, "")
  }
}
output "win_dotnet_3tier_ips" {
  value = {
    frontend  = try(vsphere_virtual_machine.win_vm_3tier["win-dotnet-fe"].default_ip_address, "")
    appserver = try(vsphere_virtual_machine.win_vm_3tier["win-dotnet-app"].default_ip_address, "")
    database  = try(vsphere_virtual_machine.win_vm_3tier["win-dotnet-db"].default_ip_address, "")
  }
}
output "win_php_3tier_ips" {
  value = {
    frontend  = try(vsphere_virtual_machine.win_vm_3tier["win-php-fe"].default_ip_address, "")
    appserver = try(vsphere_virtual_machine.win_vm_3tier["win-php-app"].default_ip_address, "")
    database  = try(vsphere_virtual_machine.win_vm_3tier["win-php-db"].default_ip_address, "")
  }
}
output "win_cln_3tier_ips" {
  value = {
    frontend  = try(vsphere_virtual_machine.win_vm_3tier["win-cln-fe"].default_ip_address, "")
    appserver = try(vsphere_virtual_machine.win_vm_3tier["win-cln-app"].default_ip_address, "")
    database  = try(vsphere_virtual_machine.win_vm_3tier["win-cln-db"].default_ip_address, "")
  }
}

output "ansible_inventory_path" {
  value = local_file.ansible_inventory.filename
}

# --- DNS registration source (actual VM hostname => IP, from Terraform state) ---
output "dns_records" {
  description = "Map of VM hostname => IPv4 address for DNS registration, sourced from Terraform state across all tiers."
  value = merge(
    { for k, vm in vsphere_virtual_machine.vm : vm.name => vm.default_ip_address },
    { for k, vm in vsphere_virtual_machine.win_vm : vm.name => vm.default_ip_address },
    { for k, vm in vsphere_virtual_machine.vm_3tier : vm.name => vm.default_ip_address },
    { for k, vm in vsphere_virtual_machine.win_vm_3tier : vm.name => vm.default_ip_address }
  )
}

# --- DNS zone (domain) the records belong to ---
output "dns_zone" {
  description = "DNS zone/domain for the registered records (matches vm_domain)."
  value       = var.vm_domain
}
