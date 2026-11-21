# Sahte provider ile, Proxmox olmadan çalışır: tofu test
# Testler plan ile çalışır: tutucunun prevent_destroy kuralı test sonundaki yıkımı engeller.

mock_provider "proxmox" {
  override_resource {
    target = proxmox_virtual_environment_vm.data
    values = {
      disk = { path_in_datastore = "vm-9120-disk-0" }
    }
  }
  override_resource {
    target = proxmox_virtual_environment_file.user_data
    values = {
      id = "local:snippets/dc-user-data.yaml"
    }
  }
}

variables {
  name            = "dc"
  vm_id           = 120
  node_name       = "proxmox"
  os_disk_file_id = "local:import/librenfra-dc-1.0.0.qcow2"
  bridge          = "vmbr1"
  ipv4_address    = "10.10.10.10/24"
  ipv4_gateway    = "10.10.10.1"
  dns_servers     = ["10.10.10.1"]
  user_data       = "#cloud-config\n"
}

run "veri_diski_olan_makine" {
  command = plan

  variables {
    data_disk = { size_gb = 10 }
  }

  assert {
    condition     = proxmox_virtual_environment_vm.data[0].vm_id == 9120
    error_message = "Tutucu 9000 + vm_id numarasını almalı"
  }
  assert {
    condition     = proxmox_virtual_environment_vm.data[0].protection && !proxmox_virtual_environment_vm.data[0].started
    error_message = "Tutucu korumalı olmalı ve açılmamalı"
  }
  assert {
    condition     = proxmox_virtual_environment_vm.this.disk[1].path_in_datastore == "vm-9120-disk-0" && proxmox_virtual_environment_vm.this.disk[1].serial == "lnfr-data"
    error_message = "Makine tutucunun diskini lnfr-data seri numarasıyla takmalı"
  }
  assert {
    condition     = proxmox_virtual_environment_vm.this.disk[0].import_from == "local:import/librenfra-dc-1.0.0.qcow2"
    error_message = "İşletim sistemi diski imaj dosyasından gelmeli"
  }
}

run "veri_diski_olmayan_makine" {
  command = plan

  assert {
    condition     = length(proxmox_virtual_environment_vm.data) == 0 && length(proxmox_virtual_environment_vm.this.disk) == 1
    error_message = "data_disk null iken tutucu ve ikinci disk olmamalı"
  }
}

run "ilk_kurulum" {
  command = apply

  variables {
    os_disk_file_id = "local:import/librenfra-dc-1.0.0.qcow2"
  }
}

run "imaj_surumu_degisince_disk_yeniden_alinmaz" {
  command = plan

  variables {
    os_disk_file_id = "local:import/librenfra-dc-1.1.0.qcow2"
  }

  assert {
    condition     = proxmox_virtual_environment_vm.this.disk[0].import_from == "local:import/librenfra-dc-1.0.0.qcow2"
    error_message = "Yeni imaj dosyası mevcut makinenin diskini değiştirmemeli; güncelleme bootc ile yapılır"
  }
}
