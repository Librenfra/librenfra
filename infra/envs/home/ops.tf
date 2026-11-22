locals {
  ops_ip = "10.10.10.30"
  # Herkesin anahtarlarına ops'un anahtarı eklenir: güncellemeleri ops yapar (bootc switch).
  ssh_authorized_keys = concat(var.ssh_authorized_keys, [trimspace(tls_private_key.ops_ssh.public_key_openssh)])
}

# ops'un ortamdaki makinelere bağlandığı anahtar. Özel anahtar yalnızca ops'a verilir.
resource "tls_private_key" "ops_ssh" {
  algorithm = "ED25519"
}

resource "proxmox_download_file" "ops" {
  content_type = "import"
  datastore_id = "local"
  node_name    = var.node_name
  url          = "${var.release_base_url}/v${var.release}/librenfra-ops-${var.release}.qcow2"
  file_name    = "librenfra-ops-${var.release}.qcow2"
}

module "ops" {
  source = "../../modules/bootc-vm"

  name            = "ops"
  vm_id           = 150
  node_name       = var.node_name
  description     = "Librenfra yönetim makinesi (GitHub Actions runner, OpenTofu)"
  startup_order   = 6
  os_disk_file_id = proxmox_download_file.ops.id
  # Runner'ın verisi ve OpenTofu state'i
  data_disk = { size_gb = 10 }

  bridge       = proxmox_network_linux_bridge.segment["lan"].name
  ipv4_address = "${local.ops_ip}/24"
  ipv4_gateway = local.gateway["lan"]
  dns_servers  = [local.gateway["lan"]]
  dns_domain   = lower(var.realm)

  user_data = templatefile("${path.module}/templates/ops-user-data.yaml.tftpl", {
    hostname            = "ops"
    fqdn                = "ops.${lower(var.realm)}"
    ipv4_address        = local.ops_ip
    ssh_authorized_keys = var.ssh_authorized_keys
    runner_url          = var.runner_repository_url
    runner_token        = var.runner_token
    ssh_key             = tls_private_key.ops_ssh.private_key_openssh
  })
}
