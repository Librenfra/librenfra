# Sahte provider ile, Proxmox olmadan çalışır: tofu test

mock_provider "proxmox" {
  override_resource {
    target = proxmox_download_file.dc
    values = { id = "local:import/librenfra-dc-0.1.0.qcow2" }
  }
  override_resource {
    target = proxmox_download_file.opnsense
    values = { id = "local:import/opnsense-26.7-nano.raw" }
  }
  override_resource {
    target = module.dc.proxmox_virtual_environment_vm.data
    values = { disk = { path_in_datastore = "vm-9120-disk-0" } }
  }
  override_resource {
    target = module.dc.proxmox_virtual_environment_file.user_data
    values = { id = "local:snippets/dc-user-data.yaml" }
  }
  override_resource {
    target = proxmox_download_file.mail
    values = { id = "local:import/librenfra-mail-0.1.0.qcow2" }
  }
  override_resource {
    target = module.mail.proxmox_virtual_environment_vm.data
    values = { disk = { path_in_datastore = "vm-9130-disk-0" } }
  }
  override_resource {
    target = module.mail.proxmox_virtual_environment_file.user_data
    values = { id = "local:snippets/mail-user-data.yaml" }
  }
  override_resource {
    target = proxmox_download_file.k8s
    values = { id = "local:import/librenfra-k8s-0.1.0.qcow2" }
  }
  override_resource {
    target = proxmox_download_file.ops
    values = { id = "local:import/librenfra-ops-0.1.0.qcow2" }
  }
  override_resource {
    target = module.ops.proxmox_virtual_environment_vm.data
    values = { disk = { path_in_datastore = "vm-9150-disk-0" } }
  }
  override_resource {
    target = module.ops.proxmox_virtual_environment_file.user_data
    values = { id = "local:snippets/ops-user-data.yaml" }
  }
  override_resource {
    target = module.k8s.proxmox_virtual_environment_file.user_data
    values = { id = "local:snippets/k8s-user-data.yaml" }
  }
}

variables {
  release               = "0.1.0"
  opnsense_version      = "26.7"
  opnsense_image_url    = "https://pkg.opnsense.org/releases/26.7/OPNsense-26.7-nano-amd64.img.bz2"
  opnsense_image_sha256 = "28d5e2f37e40d87468a924e3006ef10e2ddc6de485b85333d9e3958c84d0cb9d"
  ssh_authorized_keys   = ["ssh-ed25519 AAAA test"]
  realm                 = "AD.ORNEK.COM"
  netbios_domain        = "ORNEK"
  mail_domains          = ["ornek.com"]
  dc_admin_password     = "test"
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

run "mail" {
  command = plan

  assert {
    condition     = module.mail.vm_id == 130 && module.mail.data_vm_id == 9130
    error_message = "mail 130, veri diski tutucusu 9130 olmalı"
  }
  assert {
    condition     = module.mail.ipv4_address == "10.10.20.10"
    error_message = "mail DMZ'de 10.10.20.10 olmalı"
  }
  assert {
    condition     = tls_cert_request.host["mail"].dns_names == tolist(["mail.ornek.com"]) && tls_cert_request.host["dc"].dns_names == tolist(["dc.ad.ornek.com"])
    error_message = "Sertifikalar makinelerin adlarına verilmeli"
  }
}

run "k8s" {
  command = plan

  assert {
    condition     = module.k8s["k8s-cp"].vm_id == 140 && module.k8s["k8s-w1"].vm_id == 141
    error_message = "Kubernetes düğümleri 140 ve 141 olmalı"
  }
  assert {
    condition     = module.k8s["k8s-cp"].ipv4_address == "10.10.10.20" && module.k8s["k8s-w1"].ipv4_address == "10.10.10.21"
    error_message = "Düğümler LAN'da 10.10.10.20 ve 10.10.10.21 olmalı"
  }
  assert {
    condition     = module.k8s["k8s-cp"].data_vm_id == null && module.k8s["k8s-w1"].data_vm_id == null
    error_message = "Kubernetes düğümlerinin veri diski olmamalı"
  }
  assert {
    condition     = proxmox_download_file.k8s.url == "https://github.com/Librenfra/librenfra/releases/download/v0.1.0/librenfra-k8s-0.1.0.qcow2"
    error_message = "k8s diski sürümün Release'inden inmeli"
  }
}

run "ops" {
  command = plan

  assert {
    condition     = module.ops.vm_id == 150 && module.ops.data_vm_id == 9150
    error_message = "ops 150, veri diski tutucusu 9150 olmalı"
  }
  assert {
    condition     = module.ops.ipv4_address == "10.10.10.30"
    error_message = "ops LAN'da 10.10.10.30 olmalı"
  }
  assert {
    condition     = length(local.ssh_authorized_keys) == length(var.ssh_authorized_keys) + 1
    error_message = "Makinelere ops'un SSH anahtarı da verilmeli"
  }
}

run "firewall" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_vm.fw.started == false && proxmox_virtual_environment_vm.fw.cdrom[0].interface == "ide2"
    error_message = "Firewall kapalı oluşturulmalı (ilk açılışı içe aktarma yapar) ve ayar CD'si için ide2 olmalı"
  }
  assert {
    condition     = proxmox_download_file.opnsense.checksum == var.opnsense_image_sha256
    error_message = "OPNsense imajı checksum ile doğrulanmalı"
  }
  assert {
    condition     = tls_cert_request.fw.ip_addresses == tolist(["10.10.10.1"]) && tls_cert_request.fw.dns_names == tolist(["fw.ad.ornek.com"])
    error_message = "Arayüz sertifikası API adresini (10.10.10.1) ve fw.<alan> adını taşımalı"
  }
}

run "makineler" {
  command = plan

  assert {
    condition     = [for m in output.machines : m.name] == ["dc", "mail", "k8s-cp", "k8s-w1", "ops"]
    error_message = "Güncelleme sırası dc, mail, k8s-cp, k8s-w1, ops olmalı (k8s-cp işçiden önce)"
  }
  assert {
    condition     = [for m in output.machines : m.address] == ["10.10.10.10", "10.10.20.10", "10.10.10.20", "10.10.10.21", "10.10.10.30"]
    error_message = "Makine adresleri tofu'daki adreslerle aynı olmalı"
  }
  assert {
    condition     = output.machines[0].fqdn == "dc.ad.ornek.com" && output.machines[1].fqdn == "mail.ornek.com"
    error_message = "Ortam testleri dc'yi ve mail'i sertifikalarındaki adlarla tanır"
  }
}
