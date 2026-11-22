variable "account_id" {
  type = string
}

variable "zone_id" {
  description = "Posta alan adının Cloudflare bölgesi"
  type        = string
}

variable "mail_domain" {
  description = "Posta alan adı (bölgenin adı), ör. ornek.com"
  type        = string
}

variable "inbound_hostname" {
  description = "Worker'ın postayı ilettiği tünel adresi; varsayılan mail-in.<alan>"
  type        = string
  default     = null
}
