output "vm_ips" {
  description = "IP addresses of all provisioned VMs"
  value = {
    for k, vm in vsphere_virtual_machine.vm : k => vm.default_ip_address
  }
}

output "java_vm_ip" {
  value = vsphere_virtual_machine.vm["java-vm"].default_ip_address
}

output "dotnet_vm_ip" {
  value = vsphere_virtual_machine.vm["dotnet-vm"].default_ip_address
}

output "php_vm_ip" {
  value = vsphere_virtual_machine.vm["php-vm"].default_ip_address
}

output "ansible_inventory_path" {
  value = local_file.ansible_inventory.filename
}
