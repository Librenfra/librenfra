terraform {
  required_version = ">= 1.8"
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.123"
    }
  }
}

# Kimlik bilgisi ortam değişkenlerinden okunur:
#   PROXMOX_VE_ENDPOINT   ör. https://pve.kurum.lan:8006/
#   PROXMOX_VE_API_TOKEN  ör. tofu@pve!librenfra=<secret>
# Snippet yüklemek için provider SSH da kullanır (PROXMOX_VE_SSH_USERNAME, ssh-agent).
provider "proxmox" {
  ssh {
    agent = true
  }
}
