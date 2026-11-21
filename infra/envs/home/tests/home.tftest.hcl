# Sahte provider ile, Proxmox olmadan çalışır: tofu test

mock_provider "proxmox" {
  override_resource {
    target = proxmox_download_file.dc
    values = { id = "local:import/librenfra-dc-0.1.0.qcow2" }
  }
  override_resource {
    target = proxmox_download_file.opnsense
    values = { id = "local:import/opnsense-26.1-nano.raw" }
  }
  override_resource {
    target = module.dc.proxmox_virtual_environment_vm.data
    values = { disk = { path_in_datastore = "vm-9120-disk-0" } }
  }
  override_resource {
    target = module.dc.proxmox_virtual_environment_file.user_data
    values = { id = "local:snippets/dc-user-data.yaml" }
  }
}

variables {
  release             = "0.1.0"
  opnsense_version    = "26.1"
  opnsense_image_url  = "https://pkg.opnsense.org/releases/26.1/OPNsense-26.1-nano-amd64.img.bz2"
  ssh_authorized_keys = ["ssh-ed25519 AAAA test"]
  realm               = "AD.ORNEK.COM"
  netbios_domain      = "ORNEK"
  dc_admin_password   = "test"
}

run "ag" {
  command = plan

  assert {
    condition     = toset([for b in proxmox_network_linux_bridge.segment : b.name]) == toset(["vmbr1", "vmbr2", "vmbr3"])
    error_message = "Üç segment köprüsü vmbr1-vmbr3 olmalı"
  }
  assert {
    condition     = alltrue([for b in proxmox_network_linux_bridge.segment : b.ports == null || length(coalesce(b.ports, [])) == 0])
    error_message = "Segment köprülerinin fiziksel portu olmamalı"
  }
  assert {
    condition     = [for n in proxmox_virtual_environment_vm.fw.network_device : n.bridge] == ["vmbr0", "vmbr1", "vmbr2", "vmbr3"]
    error_message = "Firewall'un arayüz sırası WAN, LAN, DMZ, LAB olmalı"
  }
}

run "dc" {
  command = plan

  assert {
    condition     = module.dc.vm_id == 120 && module.dc.data_vm_id == 9120
    error_message = "dc 120, veri diski tutucusu 9120 olmalı"
  }
  assert {
    condition     = module.dc.ipv4_address == "10.10.10.10"
    error_message = "dc LAN'da 10.10.10.10 olmalı"
  }
  assert {
    condition     = proxmox_download_file.dc.url == "https://github.com/Librenfra/librenfra/releases/download/v0.1.0/librenfra-dc-0.1.0.qcow2"
    error_message = "dc diski sürümün Release'inden inmeli"
  }
}
