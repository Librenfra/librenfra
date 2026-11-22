# Pipeline'ın güncelleme sırası: önce dizin, sonra ona bağlı olanlar. ops en son ve kendisini
# günceller (images/ops: librenfra-self-update).
output "machines" {
  value = concat(
    [{ name = "dc", role = "dc", address = module.dc.ipv4_address, fqdn = local.dc_fqdn }],
    [{ name = "mail", role = "mail", address = module.mail.ipv4_address, fqdn = local.mail_fqdn }],
    [for name in sort(keys(local.k8s_nodes)) : {
      name = name, role = "k8s", address = module.k8s[name].ipv4_address, fqdn = "${name}.${lower(var.realm)}"
    }],
    [{ name = "ops", role = "ops", address = module.ops.ipv4_address, fqdn = "ops.${lower(var.realm)}" }],
  )
}

# Dizinin DNS alanı; firewall'da bu alanın soruları dc'ye gider.
output "domain" {
  value = lower(var.realm)
}

# İlk kurulum (tools/bootstrap.sh): Proxmox'a SSH, ops'un anahtarı ve ops'a ulaşılan köprü.
output "proxmox_ssh" {
  value = var.proxmox_ssh
}

output "ops_ssh_public_key" {
  value = trimspace(tls_private_key.ops_ssh.public_key_openssh)
}

output "lan_bridge" {
  value = proxmox_network_linux_bridge.segment["lan"].name
}
