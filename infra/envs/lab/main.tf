locals {
  dc_image = "ghcr.io/librenfra/dc:${var.dc_image_version}"
}

resource "proxmox_download_file" "dc_disk" {
  content_type = "import"
  datastore_id = "local"
  node_name    = var.node_name
  url          = var.dc_image_url
  file_name    = "librenfra-dc-${var.dc_image_version}.qcow2"
}

module "dc1" {
  source = "../../modules/bootc-vm"

  name              = "dc1"
  node_name         = var.node_name
  disk_file_id      = proxmox_download_file.dc_disk.id
  disk_datastore_id = var.disk_datastore_id
  bridge            = var.bridge
  cores             = 2
  memory_mb         = 2048

  ipv4_address = var.dc1_ipv4
  ipv4_gateway = var.ipv4_gateway
  # dc kendi DNS'ini domain kurulduktan sonra kullanır; ilk açılışta forwarder'a sorar.
  dns_servers = [var.dns_forwarder]
  dns_domain  = lower(var.realm)

  user_data = templatefile("${path.module}/templates/dc-user-data.yaml.tftpl", {
    hostname            = "dc1"
    fqdn                = "dc1.${lower(var.realm)}"
    ssh_authorized_keys = var.ssh_authorized_keys
    realm               = var.realm
    netbios_domain      = var.netbios_domain
    dns_forwarder       = var.dns_forwarder
    admin_password      = var.dc_admin_password
  })
}
