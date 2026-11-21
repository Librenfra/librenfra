# Altyapı (OpenTofu)

Bu dizin Librenfra ortamını Proxmox VE üzerinde kurar: segment köprüleri, firewall ve bootc makineleri.

- `modules/bootc-vm/`: tek bir bootc makinesi, isteğe bağlı veri diski ve cloud-init user-data'sı.
  - İşletim sistemi diski yalnızca makine oluşturulurken imaj dosyasından alınır. Sonraki güncellemeler makinenin içinde `bootc switch` ile yapılır; yeni bir disk dosyası mevcut makineyi değiştirmez.
  - Veri diski, `9000 + VM numarası` numaralı, açılmayan ve korumalı bir tutucu makinede durur (`prevent_destroy`). Makine silinip yeniden kurulsa da disk kalır ve makineye `lnfr-data` seri numarasıyla takılır.
- `envs/home/`: ev ortamı.
  - `network.tf`: `vmbr1` (LAN 10.10.10.0/24), `vmbr2` (DMZ 10.10.20.0/24), `vmbr3` (LAB 10.10.30.0/24). Köprülerin fiziksel portu yoktur; dış bağlantı firewall'un `vmbr0`'daki WAN arayüzündendir.
  - `firewall.tf`: VM 100 `fw`, OPNsense. Arayüz sırası WAN, LAN, DMZ, LAB.
  - `dc.tf`: VM 120 `dc`, 10.10.10.10, veri diski 9120.

## Testler

Proxmox olmadan, sahte provider ile:

```sh
cd infra/modules/bootc-vm && tofu init && tofu test
cd infra/envs/home && tofu init -backend=false && tofu test
```

## Kurulum

Diskler sürümün GitHub Release'inden indirilir (`librenfra-<rol>-<sürüm>.qcow2`). State `ops`'un veri diskindedir.

```sh
cd infra/envs/home
export PROXMOX_VE_ENDPOINT=https://192.168.1.200:8006/
export PROXMOX_VE_API_TOKEN='tofu@pve!librenfra=...'
export TF_VAR_dc_admin_password='...'
tofu init -backend-config=path=/var/lib/librenfra/tofu/home.tfstate
tofu apply
```

## Proxmox'ta gerekenler

- `local` deposunda `import` ve `snippets` içerik türleri açık olmalı (Datacenter → Storage → local → Content).
- Provider, snippet yüklemek için düğüme SSH ile bağlanır (`ssh-agent` ve `PROXMOX_VE_SSH_USERNAME`).
- `import` içerik türü Proxmox VE 8.4 ve sonrasında vardır.
