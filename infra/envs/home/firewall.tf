# OPNsense bootc ile kurulmaz. Disk sabitlenmiş OPNsense sürümünün nano imajından gelir;
# ilk ayar config.xml ile, gerisi firewall/ altındaki ayarla API'den uygulanır.
resource "proxmox_download_file" "opnsense" {
  content_type            = "import"
  datastore_id            = "local"
  node_name               = var.node_name
  url                     = var.opnsense_image_url
  file_name               = "opnsense-${var.opnsense_version}-nano.raw"
  decompression_algorithm = "bz2"
}

resource "proxmox_virtual_environment_vm" "fw" {
  name          = "fw"
  vm_id         = 100
  node_name     = var.node_name
  description   = "Librenfra firewall (OPNsense ${var.opnsense_version})"
  on_boot       = true
  machine       = "q35"
  scsi_hardware = "virtio-scsi-single"

  startup {
    order = 1
  }

  cpu {
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = 2048
  }

  serial_device {}

  vga {
    type = "serial0"
  }

  disk {
    interface    = "virtio0"
    datastore_id = "local-lvm"
    import_from  = proxmox_download_file.opnsense.id
    size         = 16
  }

  # Sıra OPNsense'teki arayüz sırasıdır: vtnet0 WAN, vtnet1 LAN, vtnet2 DMZ, vtnet3 LAB.
  network_device {
    bridge = "vmbr0"
  }

  dynamic "network_device" {
    for_each = ["lan", "dmz", "lab"]
    content {
      bridge = proxmox_network_linux_bridge.segment[network_device.value].name
    }
  }

  lifecycle {
    ignore_changes = [disk[0].import_from]
  }
}
