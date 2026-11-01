# Firewall konfigürasyonunun versiyonlanması

Firewall politikası `librenfra-firewall` reposunun `config.yml` dosyasında veri olarak durur. GitOps ile amaçlanan, bu dosyanın tek değişiklik yolu olması ve çalışan firewall'un ondan sapmadığının sürekli kanıtlanmasıdır.

Firewall diğer server'lardan farklıdır: NixOS tanımı yoktur. OPNsense kurulur ve reponun `main.tf`'i `config.yml`'yi `librenfra-terraform`'daki `opnsense` modülüyle uygular. WAN arayüzü kurumun statik IP'sini taşır.

## İki katman versiyonlanır

1. **İstenen hal (kaynak gerçeği):** `config.yml`: alias'lar, kurallar, NAT, WireGuard, Unbound DNS override'ları, Kea DHCP. İnsan bunu düzenler.
2. **Gerçek hal (kanıt ve geri dönüş):** Her apply'dan önce alınan OPNsense `config.xml` yedeği. Parola hash'leri içerdiği için OpenBao'daki bir anahtarla (transit) şifrelenip R2'ye yazılır ([State](04-state.md)); insan bunu düzenlemez. API'nin kapsamadığı, console veya GUI'den yazılan ayarlar (arayüz atamaları, WAN gateway) da böylece kayda girer.

## config.yml örneği

Biçim `librenfra-terraform`'daki `opnsense` modülünün değişken doğrulamalarıyla netleşecek; aşağıdaki yalnız fikir vermek için:

```yaml
aliases:
  - name: MGMT_WORKSTATION
    type: host
    content: ["<yönetim makinesinin IP'si>"]
  - name: MAIL
    type: host
    content: ["<mail VM'inin IP'si>"]
  - name: DC
    type: host
    content: ["<Samba'nın IP'si>"]
  - name: OPENBAO
    type: host
    content: ["<OpenBao'nun IP'si>"]
  - name: CLOUDFLARE
    type: urltable
    content: ["https://www.cloudflare.com/ips-v4"]

nat:
  - description: Cloudflare Email Worker'dan Mail'e gelen mail
    interface: wan
    protocol: tcp
    source: CLOUDFLARE
    destination_port: 443
    target: MAIL
    target_port: 443

wireguard:
  listen_port: 51820
  tunnel_network: "<VPN segmentinin adres aralığı>"
  peers:
    - name: "<kullanıcı adı>-laptop"
      public_key: "<cihazın açık anahtarı>"

rules:
  - description: DMZ'den dışarı SMTP
    interface: dmz
    action: pass
    protocol: tcp
    source: DMZ_NET
    destination: any
    destination_port: 25
  - description: Mail'den Samba AD'ye LDAPS
    interface: dmz
    action: pass
    protocol: tcp
    source: MAIL
    destination: DC
    destination_port: 636
  - description: Mail'den OpenBao'ya secret erişimi
    interface: dmz
    action: pass
    protocol: tcp
    source: MAIL
    destination: OPENBAO
    destination_port: 8200

unbound:
  domain_overrides:
    - domain: ad.domain.com
      server: DC
```

İnternetten içeri yalnız iki yol açıktır: `nat` altındaki tek kural ve WireGuard'ın 51820/udp portu. WAN'da başka bir port yönlendirmesi tanımlanmaz. WireGuard peer'larının yalnız açık anahtarı repoda durur; özel anahtar kullanıcının cihazındadır.

`ad.domain.com` alanının DNS'ini Samba AD'nin kendisi sunar; Unbound bu alana gelen sorguları Samba'ya yönlendirir ([karar 0002](kararlar/0002-active-directory-secimi.md)).

## Bir kural değişikliğinin yolculuğu

Örnek: DMZ'den dışarı SMTP 25 izni.

1. `feat/dmz-smtp-out` dalında `config.yml`'deki `rules` listesine yeni kural eklenir, commit: `feat(fw): DMZ'den SMTP çıkışı`.
2. PR açılır. CI `terraform validate` ile `config.yml`'nin biçimini kontrol eder. Kural tablosunu README'den üreten bir script, README ile YAML'ın ayrışmadığını da kontrol eder.
3. Merge sonrası yönetici yönetim makinesinde `terraform plan` çalıştırır ve "1 to add, 0 to change, 0 to destroy" çıktısını görür. `apply`'dan önce `opnsense` modülü `config.xml` yedeğini alır, sonra kural uygulanır.
4. Smoke test: DMZ'den firewall'a DNS, yönetim makinesinden UI erişimi ve LAN ve VPN'den beklenen çıkışlar doğrulanır. Geri dönüş ya `git revert` + yeniden apply ya da yedeğin geri yüklenmesidir.
5. Drift kontrolü iki şekilde çalışır:
   - `terraform plan`, Terraform'un yönettiği bir kaynak GUI'den değiştirilirse farkı bulur.
   - Yeni `config.xml` yedeği bir öncekiyle karşılaştırılır. GUI'den elle **eklenen** bir kural Terraform'un bilmediği bir kaynak olduğu için `plan`'da görünmez; bu karşılaştırma onu yakalar.

   Fark varsa düzeltme ya `config.yml`'ye işlenir ya da elle yapılan değişiklik geri alınır.

## Tarihçe

"Bu kural ne zaman, neden eklendi?" sorusunun cevabı `git log -p config.yml` ve bağlı PR'dır. Kuralların gerekçesi YAML'da yorum olarak değil, commit mesajında ve PR'da durur; böylece `config.yml` sade kalır.

## Provider ile ilgili notlar

- **Provider:** [browningluke/terraform-provider-opnsense](https://github.com/browningluke/terraform-provider-opnsense). 1.0 öncesidir; `librenfra-terraform`'da sürümü tam olarak sabitlenir ve yükseltmeler Renovate PR'ı ile, `plan` sıfır fark gösterdiği sürece kabul edilir.
- **DHCP:** Provider Dnsmasq DHCP'yi değil Kea'yı yönetir. Bu yüzden DHCP baştan Kea ile kurulur.
