locals {
  mail_ip   = "10.10.20.10"
  mail_fqdn = "mail.${var.mail_domains[0]}"
}

resource "proxmox_download_file" "mail" {
  content_type = "import"
  datastore_id = "local"
  node_name    = var.node_name
  url          = "${var.release_base_url}/v${var.release}/librenfra-mail-${var.release}.qcow2"
  file_name    = "librenfra-mail-${var.release}.qcow2"
}

module "mail" {
  source = "../../modules/bootc-vm"

  name            = "mail"
  vm_id           = 130
  node_name       = var.node_name
  description     = "Librenfra posta sunucusu (Postfix, Dovecot, rspamd)"
  startup_order   = 3
  memory_mb       = 3072
  os_disk_file_id = proxmox_download_file.mail.id
  data_disk       = { size_gb = 20 }

  bridge       = proxmox_network_linux_bridge.segment["dmz"].name
  ipv4_address = "${local.mail_ip}/24"
  ipv4_gateway = local.gateway["dmz"]
  # Firewall'daki çözümleyici, AD alanının sorgularını dc'ye yönlendirir.
  dns_servers = [local.gateway["dmz"]]
  dns_domain  = var.mail_domains[0]

  user_data = templatefile("${path.module}/templates/mail-user-data.yaml.tftpl", {
    hostname            = "mail"
    fqdn                = local.mail_fqdn
    ipv4_address        = local.mail_ip
    ssh_authorized_keys = local.ssh_authorized_keys
    mail_domains        = var.mail_domains
    realm               = var.realm
    dc_fqdn             = local.dc_fqdn
    svc_mail_password   = random_password.service_account["svc-mail"].result
    ca_cert             = tls_self_signed_cert.ca.cert_pem
    tls_cert            = tls_locally_signed_cert.host["mail"].cert_pem
    tls_key             = tls_private_key.host["mail"].private_key_pem
    cloudflared_token   = var.cloudflared_token
    mail_inbound_token  = var.mail_inbound_token
    dkim_key            = var.mail_dkim_key
  })
}
