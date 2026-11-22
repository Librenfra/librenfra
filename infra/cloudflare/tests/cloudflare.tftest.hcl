# Sahte provider ile, Cloudflare hesabı olmadan çalışır: tofu test
mock_provider "cloudflare" {
  override_resource {
    target = cloudflare_zero_trust_tunnel_cloudflared.mail
    values = { id = "11111111-2222-3333-4444-555555555555" }
  }
}

variables {
  account_id  = "acc"
  zone_id     = "zone"
  mail_domain = "ornek.com"
}

run "gelen_posta_yolu" {
  command = apply

  assert {
    condition     = cloudflare_zero_trust_tunnel_cloudflared_config.mail.config.ingress[0].hostname == "mail-in.ornek.com" && cloudflare_zero_trust_tunnel_cloudflared_config.mail.config.ingress[0].service == "http://localhost:8025"
    error_message = "Tünel mail-in.<alan> adresini mail makinesindeki alıcıya (8025) yönlendirmeli"
  }
  assert {
    condition     = cloudflare_zero_trust_tunnel_cloudflared_config.mail.config.ingress[1].service == "http_status:404"
    error_message = "Tünel başka adreslere 404 dönmeli"
  }
  assert {
    condition     = cloudflare_dns_record.inbound.content == "11111111-2222-3333-4444-555555555555.cfargotunnel.com" && cloudflare_dns_record.inbound.proxied
    error_message = "mail-in kaydı tünele gitmeli"
  }
  assert {
    condition     = cloudflare_email_routing_catch_all.mail.actions[0].type == "worker" && cloudflare_email_routing_catch_all.mail.actions[0].value[0] == "librenfra-email"
    error_message = "Bütün posta Worker'a gitmeli"
  }
  assert {
    condition     = one([for b in cloudflare_workers_script.email.bindings : b.type if b.name == "INBOUND_TOKEN"]) == "secret_text"
    error_message = "Token Worker'a secret olarak verilmeli"
  }
}

run "dkim" {
  command = apply

  assert {
    condition     = cloudflare_dns_record.dkim.name == "librenfra._domainkey.ornek.com" && cloudflare_dns_record.dkim.type == "TXT"
    error_message = "DKIM kaydı librenfra seçicisiyle yayınlanmalı"
  }
  assert {
    condition     = startswith(cloudflare_dns_record.dkim.content, "v=DKIM1; k=rsa; p=MII") && !strcontains(cloudflare_dns_record.dkim.content, "-----") && !strcontains(cloudflare_dns_record.dkim.content, "\n")
    error_message = "DKIM kaydı açık anahtarın yalnızca base64 içeriğini taşımalı"
  }
}
