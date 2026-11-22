# Bunlar infra/envs/home'a verilir (TF_VAR_cloudflared_token, TF_VAR_mail_inbound_token,
# TF_VAR_mail_dkim_key).
output "cloudflared_token" {
  value     = data.cloudflare_zero_trust_tunnel_cloudflared_token.mail.token
  sensitive = true
}

output "mail_inbound_token" {
  value     = random_password.inbound.result
  sensitive = true
}

output "mail_dkim_key" {
  value     = tls_private_key.dkim.private_key_pem
  sensitive = true
}
