locals {
  dc_ip = "10.10.10.10"
  # Diğer rollerin dizinde ihtiyaç duyduğu gruplar ve servis hesapları.
  dc_groups = ["mail-users"]
  dc_service_accounts = {
    svc-mail = { groups = [] }
  }
}

# Servis hesabı parolaları ortamda üretilir ve hem dc'ye hem hesabı kullanan role verilir.
resource "random_password" "service_account" {
  for_each = local.dc_service_accounts

  length  = 32
  special = false
}

resource "proxmox_download_file" "dc" {
  content_type = "import"
  datastore_id = "local"
  node_name    = var.node_name
  url          = "${var.release_base_url}/v${var.release}/librenfra-dc-${var.release}.qcow2"
  file_name    = "librenfra-dc-${var.release}.qcow2"
}

module "dc" {
  source = "../../modules/bootc-vm"

  name            = "dc"
  vm_id           = 120
  node_name       = var.node_name
  description     = "Librenfra dizin sunucusu (Samba AD)"
  startup_order   = 2
  os_disk_file_id = proxmox_download_file.dc.id
  data_disk       = { size_gb = 10 }

  bridge       = proxmox_network_linux_bridge.segment["lan"].name
  ipv4_address = "${local.dc_ip}/24"
  ipv4_gateway = local.gateway["lan"]
  # Domain DNS'i dc'nin kendisidir; ilk açılışta firewall'daki çözümleyiciye sorar.
  dns_servers = [local.gateway["lan"]]
  dns_domain  = lower(var.realm)

  user_data = templatefile("${path.module}/templates/dc-user-data.yaml.tftpl", {
    hostname            = "dc"
    ipv4_address        = local.dc_ip
    fqdn                = "dc.${lower(var.realm)}"
    ssh_authorized_keys = var.ssh_authorized_keys
    realm               = var.realm
    netbios_domain      = var.netbios_domain
    dns_forwarder       = local.gateway["lan"]
    admin_password      = var.dc_admin_password
    groups              = local.dc_groups
    service_accounts = { for name, a in local.dc_service_accounts : name => {
      groups   = a.groups
      password = random_password.service_account[name].result
    } }
  })
}
