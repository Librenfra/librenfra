variables {
  domain             = "ad.ornek.com"
  dns_servers        = ["192.168.1.1"]
  wan_address        = "192.168.1.201/24"
  wan_gateway        = "192.168.1.1"
  root_password_hash = "$2a$10$rootrootrootrootrootrootuQ"
  api_password_hash  = "$2a$10$apiapiapiapiapiapiapiuQ"
  api_key            = "anahtar"
  api_secret_hash    = "$2a$10$secretsecretsecretsecuQ"
  tls_cert           = "-----BEGIN CERTIFICATE-----\nsertifika\n-----END CERTIFICATE-----\n"
  tls_key            = "-----BEGIN PRIVATE KEY-----\nanahtar\n-----END PRIVATE KEY-----\n"
  segments = {
    lan = { ifname = "lan", device = "vtnet1", address = "10.10.10.1/24" }
    dmz = { ifname = "opt1", device = "vtnet2", address = "10.10.20.1/24" }
    lab = { ifname = "opt2", device = "vtnet3", address = "10.10.30.1/24" }
  }
}

run "config" {
  command = apply

  assert {
    condition     = startswith(output.config_xml, "<?xml version=\"1.0\"?>\n")
    error_message = "config.xml XML bildirimiyle başlamalı (içe aktarıcı ve OPNsense bunu bekler)"
  }
  assert {
    condition = alltrue([for s in [
      "<wan>\n      <enable>1</enable>\n      <if>vtnet0</if>",
      "<ipaddr>192.168.1.201</ipaddr>\n      <subnet>24</subnet>\n      <gateway>WAN_GW</gateway>",
      "<gateway>192.168.1.1</gateway>\n        <defaultgw>1</defaultgw>",
      "<lan>\n      <enable>1</enable>\n      <if>vtnet1</if>\n      <descr>LAN</descr>\n      <ipaddr>10.10.10.1</ipaddr>",
      "<opt1>\n      <enable>1</enable>\n      <if>vtnet2</if>\n      <descr>DMZ</descr>\n      <ipaddr>10.10.20.1</ipaddr>",
      "<opt2>\n      <enable>1</enable>\n      <if>vtnet3</if>\n      <descr>LAB</descr>\n      <ipaddr>10.10.30.1</ipaddr>",
      "<domain>ad.ornek.com</domain>", "<dnsserver>192.168.1.1</dnsserver>",
      "<apikeys>anahtar|$2a$10$secretsecretsecretsecuQ</apikeys>",
      "<crt>${base64encode(var.tls_cert)}</crt>", "<ssl-certref>librenfra</ssl-certref>",
      "<tunable>kern.ipc.tls.enable</tunable>\n      <value>0</value>",
    ] : strcontains(output.config_xml, s)])
    error_message = "config.xml arayüzleri, adresleri, API anahtarını, sertifikayı ve kTLS ayarını içermeli"
  }
}
