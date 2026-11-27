locals {
  # Kontrol düğümü ve çalışan düğüm aynı imajdan açılır; rolü cloud-init belirler.
  k8s_nodes = {
    k8s-cp = { vm_id = 140, ip = "10.10.10.20", role = "control-plane", order = 4 }
    k8s-w1 = { vm_id = 141, ip = "10.10.10.21", role = "worker", order = 5 }
  }
  k8s_endpoint = "${local.k8s_nodes["k8s-cp"].ip}:6443"
}

# Kümenin kendi CA'sı (kubeadm'in ca.crt/ca.key'i). Ortamın iç CA'sından ayrıdır: bu CA'nın
# imzaladığı her sertifika API sunucusunda kimlik sayılır.
resource "tls_private_key" "k8s_ca" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "k8s_ca" {
  private_key_pem       = tls_private_key.k8s_ca.private_key_pem
  is_ca_certificate     = true
  validity_period_hours = 24 * 365 * 10
  allowed_uses          = ["cert_signing", "crl_signing", "digital_signature", "key_encipherment"]

  subject {
    common_name = "kubernetes"
  }
}

# kubeadm bootstrap token'ı: [a-z0-9]{6}.[a-z0-9]{16}
resource "random_string" "k8s_token_id" {
  length  = 6
  special = false
  upper   = false
}

resource "random_string" "k8s_token_secret" {
  length  = 16
  special = false
  upper   = false
}

resource "proxmox_download_file" "k8s" {
  content_type = "import"
  datastore_id = "local"
  node_name    = var.node_name
  url          = "${var.release_base_url}/v${var.release}/librenfra-k8s-${var.release}.qcow2"
  file_name    = "librenfra-k8s-${var.release}.qcow2"
}

module "k8s" {
  source   = "../../modules/bootc-vm"
  for_each = local.k8s_nodes

  name            = each.key
  vm_id           = each.value.vm_id
  node_name       = var.node_name
  description     = "Librenfra Kubernetes ${each.value.role == "control-plane" ? "kontrol" : "çalışan"} düğümü"
  startup_order   = each.value.order
  memory_mb       = 3072
  os_disk_file_id = proxmox_download_file.k8s.id
  os_disk_size_gb = 40

  bridge       = proxmox_network_linux_bridge.segment["lan"].name
  ipv4_address = "${each.value.ip}/24"
  ipv4_gateway = local.gateway["lan"]
  # Firewall'daki çözümleyici, AD alanının sorgularını dc'ye yönlendirir; pod'lar da
  # CoreDNS üzerinden bu çözümleyiciyi kullanır.
  dns_servers = [local.gateway["lan"]]
  dns_domain  = lower(var.realm)

  user_data = templatefile("${path.module}/templates/k8s-user-data.yaml.tftpl", {
    hostname            = each.key
    fqdn                = "${each.key}.${lower(var.realm)}"
    ipv4_address        = each.value.ip
    ssh_authorized_keys = local.ssh_authorized_keys
    role                = each.value.role
    endpoint            = local.k8s_endpoint
    dc_fqdn             = local.dc_fqdn
    ca_cert             = tls_self_signed_cert.k8s_ca.cert_pem
    ca_key              = each.value.role == "control-plane" ? tls_private_key.k8s_ca.private_key_pem : null
    bootstrap_token     = "${random_string.k8s_token_id.result}.${random_string.k8s_token_secret.result}"
  })
}
