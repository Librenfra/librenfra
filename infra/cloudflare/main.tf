# İnternetten gelen posta: Email Routing -> Email Worker -> HTTPS (tünel) -> mail makinesindeki
# librenfra-mail-inbound -> Postfix. Ev bağlantısı operatörün NAT'ı arkasında olduğu için
# dışarıdan açık port yoktur; tünel bağlantıyı içeriden kurar.
locals {
  inbound_hostname = coalesce(var.inbound_hostname, "mail-in.${var.mail_domain}")
}

resource "random_password" "inbound" {
  length  = 48
  special = false
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "mail" {
  account_id = var.account_id
  name       = "librenfra-mail"
  config_src = "cloudflare"
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "mail" {
  account_id = var.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.mail.id
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "mail" {
  account_id = var.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.mail.id

  config = {
    ingress = [
      {
        hostname = local.inbound_hostname
        service  = "http://localhost:8025"
      },
      {
        service = "http_status:404"
      },
    ]
  }
}

resource "cloudflare_dns_record" "inbound" {
  zone_id = var.zone_id
  name    = local.inbound_hostname
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.mail.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
  comment = "Librenfra: gelen posta tüneli"
}

resource "cloudflare_workers_script" "email" {
  account_id         = var.account_id
  script_name        = "librenfra-email"
  main_module        = "email.js"
  content_file       = "${path.module}/worker/email.js"
  content_sha256     = filesha256("${path.module}/worker/email.js")
  compatibility_date = "2026-11-01"

  bindings = [
    {
      name = "INBOUND_URL"
      type = "plain_text"
      text = "https://${local.inbound_hostname}/"
    },
    {
      name = "INBOUND_TOKEN"
      type = "secret_text"
      text = random_password.inbound.result
    },
  ]
}

# Email Routing'i açar ve MX/SPF kayıtlarını ekler.
resource "cloudflare_email_routing_dns" "mail" {
  zone_id = var.zone_id
}

resource "cloudflare_email_routing_settings" "mail" {
  zone_id    = var.zone_id
  depends_on = [cloudflare_email_routing_dns.mail]
}

resource "cloudflare_email_routing_catch_all" "mail" {
  zone_id = var.zone_id
  name    = "Librenfra"
  enabled = true

  matchers = [{ type = "all" }]
  actions  = [{ type = "worker", value = [cloudflare_workers_script.email.script_name] }]

  depends_on = [cloudflare_email_routing_settings.mail]
}

# Giden posta doğrudan alıcı sunuculara gider. rspamd, kimliği doğrulanmış kullanıcıların
# postasını bu anahtarla "librenfra" seçicisiyle imzalar (images/mail/rootfs/etc/rspamd).
resource "tls_private_key" "dkim" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "cloudflare_dns_record" "dkim" {
  zone_id = var.zone_id
  name    = "librenfra._domainkey.${var.mail_domain}"
  type    = "TXT"
  ttl     = 3600
  # Açık anahtarın base64 içeriği; Cloudflare uzun TXT kaydını 255 karakterlik parçalara böler.
  content = "v=DKIM1; k=rsa; p=${replace(tls_private_key.dkim.public_key_pem, "/-----[A-Z ]+-----|\\n/", "")}"
}
