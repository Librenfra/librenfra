# OPNsense'in ilk ayarını (config.xml) üretir. Ortam (infra/envs/home) ve firewall testi
# (tests/firewall) aynı modülü kullanır.
terraform {
  required_version = ">= 1.8"
}

variable "hostname" {
  type    = string
  default = "fw"
}

variable "domain" {
  type = string
}

variable "dns_servers" {
  type = list(string)
}

variable "wan_address" {
  description = "WAN adresi ve ön ek uzunluğu, ör. 192.168.1.201/24"
  type        = string
}

variable "wan_gateway" {
  type = string
}

variable "segments" {
  description = "Segment adı => OPNsense arayüz adı (lan, opt1...), aygıt (vtnet1...), adres/ön ek"
  type = map(object({
    ifname  = string
    device  = string
    address = string
  }))
}

variable "root_password_hash" {
  description = "root parolasının bcrypt özeti"
  type        = string
  sensitive   = true
}

variable "api_password_hash" {
  description = "API kullanıcısının (librenfra) arayüz parolasının bcrypt özeti"
  type        = string
  sensitive   = true
}

variable "api_key" {
  type      = string
  sensitive = true
}

variable "api_secret_hash" {
  description = "API secret'ının bcrypt özeti"
  type        = string
  sensitive   = true
}

variable "tls_cert" {
  description = "Arayüz sertifikası (PEM)"
  type        = string
}

variable "tls_key" {
  type      = string
  sensitive = true
}

output "config_xml" {
  sensitive = true
  value = templatefile("${path.module}/../../../firewall/config.xml.tftpl", {
    hostname           = var.hostname
    domain             = var.domain
    dns_servers        = var.dns_servers
    root_password_hash = var.root_password_hash
    api_password_hash  = var.api_password_hash
    api_key            = var.api_key
    api_secret_hash    = var.api_secret_hash
    tls_cert           = var.tls_cert
    tls_key            = var.tls_key
    wan_address        = split("/", var.wan_address)[0]
    wan_prefix         = split("/", var.wan_address)[1]
    wan_gateway        = var.wan_gateway
    segments = { for k, s in var.segments : k => {
      ifname  = s.ifname
      device  = s.device
      address = split("/", s.address)[0]
      prefix  = split("/", s.address)[1]
    } }
  })
}
