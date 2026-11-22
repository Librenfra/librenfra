terraform {
  required_version = ">= 1.8"
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.29"
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
  # State ops'un veri diskindedir:
  #   tofu init -backend-config=path=/var/lib/librenfra/tofu/cloudflare.tfstate
  backend "local" {}
}

# API token'ı ortam değişkeninden okunur: CLOUDFLARE_API_TOKEN.
# Gereken izinler: Account / Cloudflare Tunnel: Edit, Account / Workers Scripts: Edit,
# Zone / DNS: Edit, Zone / Email Routing Rules: Edit, Zone / Zone Settings: Edit.
provider "cloudflare" {}
