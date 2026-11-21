# Proxmox üzerinde bir bootc makinesi ve isteğe bağlı veri diski.
#
# İşletim sistemi bu modülle değil `bootc switch` ile güncellenir. İşletim sistemi
# diski yalnızca makine oluşturulurken imaj dosyasından kopyalanır; os_disk_file_id
# değişse bile makine yeniden oluşturulmaz.
#
# Servis verisi ayrı bir diskte durur. Proxmox bir makineyi silerken yalnızca o
# makinenin kendi disklerini siler; bu yüzden veri diski hiç açılmayan bir tutucu
# makineye aittir ve makine onu yalnızca takar. Makine silinip yeniden kurulsa da
# veri kalır. İmaj, diski seri numarasından (/dev/disk/by-id/virtio-lnfr-data) bulur.

locals {
  data_vm_id = 9000 + var.vm_id
  data_path  = "vm-${local.data_vm_id}-disk-0"
}

resource "proxmox_virtual_environment_vm" "data" {
  count = var.data_disk == null ? 0 : 1

  name        = "data-${var.vm_id}"
  node_name   = var.node_name
  vm_id       = local.data_vm_id
  description = "VM ${var.vm_id} (${var.name}) için veri diskini tutar. Hiç açılmaz."
  tags        = ["librenfra", "data-disk"]

  started    = false
  on_boot    = false
  protection = true

  disk {
    datastore_id = var.data_disk.datastore_id
    interface    = "scsi0"
    size         = var.data_disk.size_gb
    file_format  = "raw"
  }

  lifecycle {
    # Tutucuyu silmek veriyi silmektir.
    prevent_destroy = true

    postcondition {
      condition     = self.disk[0].path_in_datastore == local.data_path
      error_message = "Tutucunun diski ${self.disk[0].path_in_datastore}; makine ${local.data_path} bekliyor."
    }
  }
}

resource "proxmox_virtual_environment_file" "user_data" {
  content_type = "snippets"
  datastore_id = var.snippets_datastore_id
  node_name    = var.node_name

  source_raw {
    data      = var.user_data
    file_name = "librenfra-${var.name}-user-data.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "this" {
  name        = var.name
  node_name   = var.node_name
  vm_id       = var.vm_id
  description = var.description
  tags        = ["librenfra", "bootc"]

  started = true
  on_boot = true

  startup {
    order = var.startup_order
  }

  machine = "q35"

  operating_system {
    type = "l26"
  }

  cpu {
    cores = var.cores
    type  = "host"
  }

  memory {
    dedicated = var.memory_mb
  }

  serial_device {
    device = "socket"
  }

  vga {
    type = "serial0"
  }

  disk {
    interface    = "virtio0"
    datastore_id = var.os_datastore_id
    import_from  = var.os_disk_file_id
    size         = var.os_disk_size_gb
    iothread     = true
    discard      = "on"
  }

  dynamic "disk" {
    for_each = var.data_disk == null ? [] : [var.data_disk]
    content {
      interface         = "virtio1"
      datastore_id      = disk.value.datastore_id
      path_in_datastore = local.data_path
      file_format       = "raw"
      size              = disk.value.size_gb
      serial            = "lnfr-data"
      iothread          = true
      discard           = "on"
    }
  }

  boot_order = ["virtio0"]

  network_device {
    bridge   = var.bridge
    model    = "virtio"
    firewall = false
  }

  initialization {
    datastore_id      = var.os_datastore_id
    user_data_file_id = proxmox_virtual_environment_file.user_data.id

    ip_config {
      ipv4 {
        address = var.ipv4_address
        gateway = var.ipv4_gateway
      }
    }

    dns {
      servers = var.dns_servers
      domain  = var.dns_domain
    }
  }

  depends_on = [proxmox_virtual_environment_vm.data]

  lifecycle {
    ignore_changes = [disk[0].import_from]
  }
}
