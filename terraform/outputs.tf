output "vm_ips" {
  description = "IP addresses of all provisioned VMs"
  value = merge(
    { for k, vm in vsphere_virtual_machine.vm : k => vm.default_ip_address },
    { for k, vm in vsphere_virtual_machine.win_vm : k => vm.default_ip_address },
    { for k, vm in vsphere_virtual_machine.vm_3tier : k => vm.default_ip_address },
    { for k, vm in vsphere_virtual_machine.win_vm_3tier : k => vm.default_ip_address }
  )
}

output "java_vm_ip" {
  value = (
    var.deploy_mode == "linux" && var.deploy_java ? vsphere_virtual_machine.vm["java-vm"].default_ip_address :
    var.deploy_mode == "windows" && var.deploy_java ? vsphere_virtual_machine.win_vm["win-java-vm"].default_ip_address :
    ""
  )
}

output "dotnet_vm_ip" {
  value = (
    var.deploy_mode == "linux" && var.deploy_dotnet ? vsphere_virtual_machine.vm["dotnet-vm"].default_ip_address :
    var.deploy_mode == "windows" && var.deploy_dotnet ? vsphere_virtual_machine.win_vm["win-dotnet-vm"].default_ip_address :
    ""
  )
}

output "php_vm_ip" {
  value = (
    var.deploy_mode == "linux" && var.deploy_php ? vsphere_virtual_machine.vm["php-vm"].default_ip_address :
    var.deploy_mode == "windows" && var.deploy_php ? vsphere_virtual_machine.win_vm["win-php-vm"].default_ip_address :
    ""
  )
}

# --- 3-Tier outputs ---
output "java_3tier_ips" {
  description = "Java 3-tier VM IPs (frontend, appserver, database)"
  value = var.deploy_java ? (
    var.deploy_mode == "linux-3tier" ? {
      frontend  = vsphere_virtual_machine.vm_3tier["java-fe"].default_ip_address
      appserver = vsphere_virtual_machine.vm_3tier["java-app"].default_ip_address
      database  = vsphere_virtual_machine.vm_3tier["java-db"].default_ip_address
    } : var.deploy_mode == "windows-3tier" ? {
      frontend  = vsphere_virtual_machine.win_vm_3tier["win-java-fe"].default_ip_address
      appserver = vsphere_virtual_machine.win_vm_3tier["win-java-app"].default_ip_address
      database  = vsphere_virtual_machine.win_vm_3tier["win-java-db"].default_ip_address
    } : {}
  ) : {}
}

output "dotnet_3tier_ips" {
  description = ".NET 3-tier VM IPs (frontend, appserver, database)"
  value = var.deploy_dotnet ? (
    var.deploy_mode == "linux-3tier" ? {
      frontend  = vsphere_virtual_machine.vm_3tier["dotnet-fe"].default_ip_address
      appserver = vsphere_virtual_machine.vm_3tier["dotnet-app"].default_ip_address
      database  = vsphere_virtual_machine.vm_3tier["dotnet-db"].default_ip_address
    } : var.deploy_mode == "windows-3tier" ? {
      frontend  = vsphere_virtual_machine.win_vm_3tier["win-dotnet-fe"].default_ip_address
      appserver = vsphere_virtual_machine.win_vm_3tier["win-dotnet-app"].default_ip_address
      database  = vsphere_virtual_machine.win_vm_3tier["win-dotnet-db"].default_ip_address
    } : {}
  ) : {}
}

output "php_3tier_ips" {
  description = "PHP 3-tier VM IPs (frontend, appserver, database)"
  value = var.deploy_php ? (
    var.deploy_mode == "linux-3tier" ? {
      frontend  = vsphere_virtual_machine.vm_3tier["php-fe"].default_ip_address
      appserver = vsphere_virtual_machine.vm_3tier["php-app"].default_ip_address
      database  = vsphere_virtual_machine.vm_3tier["php-db"].default_ip_address
    } : var.deploy_mode == "windows-3tier" ? {
      frontend  = vsphere_virtual_machine.win_vm_3tier["win-php-fe"].default_ip_address
      appserver = vsphere_virtual_machine.win_vm_3tier["win-php-app"].default_ip_address
      database  = vsphere_virtual_machine.win_vm_3tier["win-php-db"].default_ip_address
    } : {}
  ) : {}
}

output "ansible_inventory_path" {
  value = local_file.ansible_inventory.filename
}
