# Ortamın iç CA'sı. Dizinin LDAPS'i ve posta sunucusunun TLS'i bu CA'nın sertifikalarını
# kullanır; makineler CA'yı /etc/librenfra/ca.pem'den tanır. Anahtarlar state'tedir.
resource "tls_private_key" "ca" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_self_signed_cert" "ca" {
  private_key_pem       = tls_private_key.ca.private_key_pem
  is_ca_certificate     = true
  validity_period_hours = 24 * 365 * 10
  allowed_uses          = ["cert_signing", "crl_signing"]

  subject {
    common_name  = "Librenfra CA"
    organization = var.netbios_domain
  }
}

locals {
  tls_hosts = {
    dc   = local.dc_fqdn
    mail = local.mail_fqdn
  }
}

resource "tls_private_key" "host" {
  for_each = local.tls_hosts

  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_cert_request" "host" {
  for_each = local.tls_hosts

  private_key_pem = tls_private_key.host[each.key].private_key_pem
  dns_names       = [each.value]

  subject {
    common_name = each.value
  }
}

# Sertifika süresinin son 30 gününde tofu apply yenisini üretir; yeni sertifika makineye
# cloud-init ile ulaşır (user-data değişince Proxmox yeni bir instance-id verir).
resource "tls_locally_signed_cert" "host" {
  for_each = local.tls_hosts

  cert_request_pem      = tls_cert_request.host[each.key].cert_request_pem
  ca_private_key_pem    = tls_private_key.ca.private_key_pem
  ca_cert_pem           = tls_self_signed_cert.ca.cert_pem
  validity_period_hours = 24 * 365 * 2
  early_renewal_hours   = 24 * 30
  allowed_uses          = ["digital_signature", "key_encipherment", "server_auth"]
}

# ops'un firewall API'sini ve makinelerin TLS'ini doğrulamak için kullandığı CA.
output "ca_cert" {
  value = tls_self_signed_cert.ca.cert_pem
}
