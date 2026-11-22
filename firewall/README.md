# firewall

VM 100 `fw` OPNsense'tir ve bootc ile kurulmaz. Sürüm, sabitlenmiş OPNsense sürümü ile bu dizindeki ayarın birleşimidir.

| Dosya | Ne yapar |
| --- | --- |
| `config.xml.tftpl` | İlk ayar: arayüz atamaları, WAN ve segment adresleri, WAN ağ geçidi, LAN'dan çıkış kuralı, otomatik giden NAT, Librenfra CA ile imzalı arayüz sertifikası, `librenfra` API kullanıcısı. `infra/modules/opnsense-config` doldurur. |
| `import-config` | Temiz bir kurulumun ilk açılışında `config.xml`'i içe aktarır. |
| `ayar.yml` | Takma adlar, segment kuralları, DNS ve LAB'ın DHCP'si. OPNsense API'si ile uygulanır. |

## İlk ayar

OPNsense'in içe aktarıcısı, `/conf/config.xml` yokken her açılışta seri konsolda birkaç saniye bir tuşa basılmasını bekler, sonra seçilen diskten ya da CD'den `conf/config.xml`'i alır. `import-config` bu konuşmayı seri konsoldan yürütür:

1. Proxmox'ta `genisoimage` ile içinde yalnızca `conf/config.xml` olan bir CD hazırlar ve makinenin `ide2` sürücüsüne takar.
2. Kapalı makineyi açar ve `qm terminal` ile seri konsola bağlanır.
3. İçe aktarıcının istemine tuşa basar, CD'yi (`cd0`) seçer ve `Restoring config.xml...done.` çıktısını bekler.
4. Açılış bitip giriş istemi gelince CD'yi çıkarır ve siler.

`infra/envs/home` bunu `terraform_data.fw_import` ile makine her oluşturulduğunda yapar. Makine bu yüzden kapalı oluşturulur (`started = false`). Proxmox'a provider'ın snippet yüklemek için kullandığı SSH erişimiyle bağlanılır.

`config.xml`'de parolalar ve API secret'ı yalnızca bcrypt özetleriyle bulunur. Açık değerler OpenTofu state'indedir (`fw_root_password`, `fw_api_credentials` çıktıları).

OPNsense 26.7'de çekirdek TLS'i (kTLS) açıkken arayüzün HTTP/1.1 yanıtları 64 KiB'den büyük gövdelerde bozuluyor: chunk başlığından sonra fazla veri geliyor ve istemci yanıtı ayrıştıramıyor. API istemcisi (httpx) HTTP/1.1 kullandığı için `config.xml` `kern.ipc.tls.enable=0` ayarını taşır. Lab'da `/api/firewall/filter/get` bu ayar olmadan yedi denemenin beşinde bozuldu, ayarla altı denemenin hepsinde tamdı ([forum](https://forum.opnsense.org/index.php?topic=52389.0)).

## Ayar

```sh
ansible-playbook firewall/ayar.yml -e @ortam.yml                  # uygular
ansible-playbook firewall/ayar.yml -e @ortam.yml --check --diff   # farkı raporlar, değiştirmez
```

`ortam.yml`: `fw_host` (`10.10.10.1`), `fw_credentials` (`tofu output -raw fw_api_credentials` ile yazılan, yalnızca sahibinin okuyabildiği dosya), `fw_ca` (`tofu output -raw ca_cert`), `domain` (dizinin DNS alanı), `dc_address`.

Gerekenler: `ansible-core`, `ansibleguy.opnsense` koleksiyonu, Python `httpx`.

Kurallar ve takma adlar `ayar.yml`'dekilerle birebir tutulur: firewall'da elle eklenen bir kural `--check` ile görünür ve bir sonraki uygulamada silinir.

| Segment | İzin |
| --- | --- |
| LAN | Her yere (ev ağı ve Proxmox API'si dahil) |
| DMZ | Firewall'daki DNS; mail'den (`10.10.20.10`) dc'ye Kerberos (88), parola değişimi (464), LDAPS (636); internet |
| LAB | Firewall'daki DNS ve DHCP; internet |

DMZ ve LAB'dan iç ağlara (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, firewall'un kendi adresleri dahil) başka erişim yoktur. Arayüze ve API'ye yalnızca LAN'dan erişilir. Dizinin alanı Unbound'da dc'ye yönlendirilir; diğer adları Unbound kendisi çözer.

Firewall'u yeniden kurmak ortamın dışından, ev ağından yapılır: `ops`'un Proxmox'a ve internete yolu firewall'dan geçer.

## Test

`tests/firewall/test.sh` temiz bir OPNsense'i QEMU'da açar, ilk ayarı içe aktarır, `ayar.yml`'yi uygular ve segmentler arası erişimi ağ ad alanlarından sınar.
