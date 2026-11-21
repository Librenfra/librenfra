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
