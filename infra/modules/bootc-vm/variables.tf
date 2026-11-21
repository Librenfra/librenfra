variable "name" {
  description = "Makinenin adı; aynı zamanda hostname"
  type        = string
}

variable "vm_id" {
  description = "Proxmox VM numarası. Veri diski tutucusu 9000 + bu numarayı alır."
  type        = number
}

variable "node_name" {
  type = string
}

variable "description" {
  type    = string
  default = ""
}

variable "cores" {
  type    = number
  default = 2
}

variable "memory_mb" {
  type    = number
  default = 2048
}

variable "startup_order" {
  description = "Host açılırken başlatılma sırası"
  type        = number
  default     = 10
}

variable "os_disk_file_id" {
  description = "bootc imajından üretilmiş qcow2 diskin Proxmox'taki kimliği (ör. local:import/librenfra-dc-1.0.0.qcow2). Yalnızca makine oluşturulurken kullanılır."
  type        = string
}

variable "os_datastore_id" {
  type    = string
  default = "local-lvm"
}

variable "os_disk_size_gb" {
  type    = number
  default = 20
}

variable "data_disk" {
  description = "Servis verisinin diski. null ise veri diski yoktur. Disk, hiç açılmayan bir tutucu makineye (VM 9000 + vm_id) aittir; makine silinse de disk kalır."
  type = object({
    size_gb      = number
    datastore_id = optional(string, "vmdata")
  })
  default = null
}

variable "bridge" {
  type = string
}

variable "ipv4_address" {
  description = "CIDR biçiminde adres (ör. 10.10.10.10/24)"
  type        = string
}

variable "ipv4_gateway" {
  type = string
}

variable "dns_servers" {
  type = list(string)
}

variable "dns_domain" {
  type    = string
  default = null
}

variable "user_data" {
  description = "cloud-init user-data. Rolün ayar dosyalarını ve secret'larını taşır."
  type        = string
  sensitive   = true
}

variable "snippets_datastore_id" {
  description = "user-data'nın snippet olarak yükleneceği depo"
  type        = string
  default     = "local"
}
