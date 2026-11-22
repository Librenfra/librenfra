# OPNsense bootc ile kurulmaz. Disk sabitlenmiş OPNsense sürümünün nano imajından gelir.
# İlk ayar (firewall/config.xml.tftpl) makine oluşturulduğunda ilk açılışta içe aktarılır;
# kurallar, DNS ve DHCP firewall/ayar.yml ile API'den uygulanır.
resource "proxmox_download_file" "opnsense" {
  content_type            = "import"
  datastore_id            = "local"
  node_name               = var.node_name
  url                     = var.opnsense_image_url
  file_name               = "opnsense-${var.opnsense_version}-nano.raw"
  decompression_algorithm = "bz2"
  checksum                = var.opnsense_image_sha256
  checksum_algorithm      = "sha256"
}

locals {
  fw_fqdn = "fw.${lower(var.realm)}"
  # OPNsense arayüz adları: vtnet0 WAN, sonra segmentler network_device sırasıyla.
  fw_segments = {
    lan = { ifname = "lan", device = "vtnet1" }
    dmz = { ifname = "opt1", device = "vtnet2" }
    lab = { ifname = "opt2", device = "vtnet3" }
  }
}

resource "random_password" "fw" {
  for_each = toset(["root", "api_user", "api_key", "api_secret"])

  length  = each.key == "api_key" ? 64 : 32
  special = false
}

resource "tls_private_key" "fw" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_cert_request" "fw" {
  private_key_pem = tls_private_key.fw.private_key_pem
  dns_names       = [local.fw_fqdn]
  ip_addresses    = [local.gateway["lan"]]

  subject {
    common_name = local.fw_fqdn
  }
}

# Arayüz sertifikası config.xml'in içindedir; yenilenen sertifika bir sonraki yeniden kurulumda
# ya da arayüzden elle yüklenerek geçer.
resource "tls_locally_signed_cert" "fw" {
  cert_request_pem      = tls_cert_request.fw.cert_request_pem
  ca_private_key_pem    = tls_private_key.ca.private_key_pem
  ca_cert_pem           = tls_self_signed_cert.ca.cert_pem
  validity_period_hours = 24 * 365 * 2
  allowed_uses          = ["digital_signature", "key_encipherment", "server_auth"]
}

module "fw_config" {
  source = "../../modules/opnsense-config"

  domain             = lower(var.realm)
  dns_servers        = [var.wan_gateway]
  wan_address        = var.wan_address
  wan_gateway        = var.wan_gateway
  root_password_hash = random_password.fw["root"].bcrypt_hash
  api_password_hash  = random_password.fw["api_user"].bcrypt_hash
  api_key            = random_password.fw["api_key"].result
  api_secret_hash    = random_password.fw["api_secret"].bcrypt_hash
  tls_cert           = tls_locally_signed_cert.fw.cert_pem
  tls_key            = tls_private_key.fw.private_key_pem
  segments = { for k, s in local.fw_segments : k => merge(s, {
    address = "${local.gateway[k]}/24"
  }) }
}

resource "proxmox_virtual_environment_vm" "fw" {
  name        = "fw"
  vm_id       = 100
  node_name   = var.node_name
  description = "Librenfra firewall (OPNsense ${var.opnsense_version})"
  on_boot     = true
  # İlk açılışı terraform_data.fw_import yapar: içe aktarıcı yalnızca ilk açılışta çalışır.
  started       = false
  machine       = "q35"
  scsi_hardware = "virtio-scsi-single"

  startup {
    order = 1
  }

  cpu {
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = 2048
  }

  serial_device {}

  vga {
    type = "serial0"
  }

  # İçe aktarma sırasında ayar CD'si buraya takılır, sonra çıkarılır.
  cdrom {
    interface = "ide2"
    file_id   = "none"
  }

  disk {
    interface    = "virtio0"
    datastore_id = "local-lvm"
    import_from  = proxmox_download_file.opnsense.id
    size         = 16
  }

  # Sıra OPNsense'teki arayüz sırasıdır: vtnet0 WAN, vtnet1 LAN, vtnet2 DMZ, vtnet3 LAB.
  network_device {
    bridge = "vmbr0"
  }

  dynamic "network_device" {
    for_each = ["lan", "dmz", "lab"]
    content {
      bridge = proxmox_network_linux_bridge.segment[network_device.value].name
    }
  }

  lifecycle {
    ignore_changes = [disk[0].import_from, started]
  }
}

# Makine her oluşturulduğunda config.xml'i ilk açılışta içe aktarır. Proxmox'a SSH ile bağlanır
# (provider'ın snippet yüklemek için kullandığı erişim) ve OPNsense'in seri konsolunu yürütür.
# Firewall'u yeniden kurmak ortamın dışından, ev ağından yapılır: ops'un yolu firewall'dan geçer.
resource "terraform_data" "fw_import" {
  triggers_replace = [proxmox_virtual_environment_vm.fw.id]

  provisioner "local-exec" {
    command = "printenv LIBRENFRA_FW_CONFIG | python3 ${path.module}/../../../firewall/import-config --proxmox \"$LIBRENFRA_PROXMOX_SSH\" --vmid ${proxmox_virtual_environment_vm.fw.vm_id} -"
    environment = {
      LIBRENFRA_FW_CONFIG   = module.fw_config.config_xml
      LIBRENFRA_PROXMOX_SSH = var.proxmox_ssh
    }
  }
}

# ops'un firewall/ayar.yml'yi çalıştırmak için kullandığı API anahtarı, OPNsense'in dosya biçiminde.
output "fw_api_credentials" {
  value     = "key=${random_password.fw["api_key"].result}\nsecret=${random_password.fw["api_secret"].result}\n"
  sensitive = true
}

output "fw_root_password" {
  value     = random_password.fw["root"].result
  sensitive = true
}
