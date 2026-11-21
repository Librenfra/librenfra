variable "node_name" {
  description = "Proxmox düğümünün adı"
  type        = string
}

variable "bridge" {
  type    = string
  default = "vmbr0"
}

variable "disk_datastore_id" {
  type    = string
  default = "local-lvm"
}

variable "ssh_authorized_keys" {
  description = "librenfra kullanıcısına eklenecek SSH anahtarları"
  type        = list(string)
}

variable "dc_image_url" {
  description = "dc imajından üretilmiş qcow2 diskin indirme adresi"
  type        = string
}

variable "dc_image_version" {
  description = "Kurulan sistemin bootc upgrade ile izleyeceği imaj sürümü"
  type        = string
}

variable "realm" {
  type    = string
  default = "KURUM.LAN"
}

variable "netbios_domain" {
  type    = string
  default = "KURUM"
}

variable "dc1_ipv4" {
  description = "dc1 adresi, CIDR biçiminde"
  type        = string
}

variable "ipv4_gateway" {
  type = string
}

variable "dns_forwarder" {
  description = "Domain dışındaki adlar için Samba'nın soracağı DNS sunucusu"
  type        = string
}

variable "dc_admin_password" {
  description = "Domain yöneticisi (Administrator) parolası"
  type        = string
  sensitive   = true
}
