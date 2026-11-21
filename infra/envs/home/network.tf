# Segment köprüleri yalnızca sanal makineleri birbirine bağlar; fiziksel portları yoktur.
# Dış bağlantı firewall'un vmbr0'daki WAN arayüzündendir.
locals {
  segments = {
    lan = { bridge = "vmbr1", prefix = "10.10.10", comment = "Librenfra LAN" }
    dmz = { bridge = "vmbr2", prefix = "10.10.20", comment = "Librenfra DMZ" }
    lab = { bridge = "vmbr3", prefix = "10.10.30", comment = "Librenfra LAB" }
  }
  gateway = { for k, s in local.segments : k => "${s.prefix}.1" }
}

resource "proxmox_network_linux_bridge" "segment" {
  for_each = local.segments

  node_name = var.node_name
  name      = each.value.bridge
  comment   = each.value.comment
  autostart = true
}
