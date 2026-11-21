output "vm_id" {
  value = proxmox_virtual_environment_vm.this.vm_id
}

output "name" {
  value = proxmox_virtual_environment_vm.this.name
}

output "ipv4_address" {
  value = split("/", var.ipv4_address)[0]
}

output "data_vm_id" {
  value = var.data_disk == null ? null : local.data_vm_id
}
