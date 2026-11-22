terraform {
  required_version = ">= 1.8"
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.123"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.1"
    }
  }
  # State ops'un veri diskindedir. Yol init sırasında verilir:
  #   tofu init -backend-config=path=/var/lib/librenfra/tofu/home.tfstate
  backend "local" {}
}

# Kimlik bilgisi ortam değişkenlerinden okunur:
#   PROXMOX_VE_ENDPOINT   ör. https://192.168.1.200:8006/
#   PROXMOX_VE_API_TOKEN  ör. tofu@pve!librenfra=<secret>
# Snippet yüklemek için provider SSH da kullanır (PROXMOX_VE_SSH_USERNAME, ssh-agent).
provider "proxmox" {
  ssh {
    agent = true
  }
}
