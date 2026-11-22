variable "node_name" {
  description = "Proxmox düğümünün adı"
  type        = string
  default     = "proxmox"
}

variable "release" {
  description = "Kurulacak Librenfra sürümü; diskler bu sürümün GitHub Release'inden indirilir"
  type        = string
}

variable "release_base_url" {
  type    = string
  default = "https://github.com/Librenfra/librenfra/releases/download"
}

variable "opnsense_image_url" {
  description = "OPNsense nano imajının (bz2) indirme adresi"
  type        = string
}

variable "opnsense_version" {
  type = string
}

variable "opnsense_image_sha256" {
  description = "Nano imajının (bz2) SHA-256'sı; OPNsense'in imzalı checksum dosyasından"
  type        = string
}

variable "wan_address" {
  description = "Firewall'un ev ağındaki adresi"
  type        = string
  default     = "192.168.1.201/24"
}

variable "wan_gateway" {
  description = "Ev ağının ağ geçidi; firewall'un varsayılan yolu ve DNS'i"
  type        = string
  default     = "192.168.1.1"
}

variable "proxmox_ssh" {
  description = "Firewall'un ilk ayarını içe aktarmak için Proxmox'a SSH hedefi"
  type        = string
  default     = "root@192.168.1.200"
}

variable "ssh_authorized_keys" {
  description = "librenfra kullanıcısına eklenecek SSH anahtarları"
  type        = list(string)
}

variable "realm" {
  description = "AD alanı, büyük harfle"
  type        = string
}

variable "netbios_domain" {
  type = string
}

variable "dc_admin_password" {
  description = "Domain yöneticisi (Administrator) parolası"
  type        = string
  sensitive   = true
}

variable "mail_domains" {
  description = "Posta alınan alan adları; ilki posta sunucusunun adında kullanılır (mail.<alan>)"
  type        = list(string)
}

variable "cloudflared_token" {
  description = "Posta sunucusundaki Cloudflare tünelinin token'ı (infra/cloudflare üretir)"
  type        = string
  sensitive   = true
  default     = null
}

variable "mail_inbound_token" {
  description = "Email Worker'ın posta sunucusuna bağlanırken kullandığı token (infra/cloudflare üretir)"
  type        = string
  sensitive   = true
  default     = null
}

variable "mail_dkim_key" {
  description = "Giden postayı imzalayan DKIM anahtarı (infra/cloudflare üretir ve DNS'e yayınlar)"
  type        = string
  sensitive   = true
  default     = null
}

variable "runner_repository_url" {
  description = "ops'taki runner'ın kaydolduğu GitHub deposu"
  type        = string
  default     = "https://github.com/Librenfra/librenfra"
}

variable "runner_token" {
  description = "Runner kayıt token'ı (bir saat geçerli; tools/bootstrap.sh alır). Runner kayıtlıysa gerekmez."
  type        = string
  sensitive   = true
  default     = null
}
