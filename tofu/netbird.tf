# who may reach what over the vpn (ADR 0040). needs the netbird vm up and the tofu service user's PAT.
# first run is staged, see docs/bootstrap.md step 4 and README.

locals {
  domain         = local.priv.domain
  dns_relay_port = local.apps.apps["dns-relay"].port
  nb_peers       = local.priv.netbird_peers # ids per group, enrolling a peer doesn't add it here

  nb_peer_groups = {
    admin     = netbird_group.admin.id
    household = netbird_group.household.id
    routing   = netbird_group.routing.id
  }
}

# peer groups. members come from private.yml, so a plan shows a peer added by hand
resource "netbird_group" "admin" {
  name  = "admin"
  peers = local.nb_peers.admin
}

resource "netbird_group" "household" {
  name  = "household"
  peers = local.nb_peers.household
}

resource "netbird_group" "routing" {
  name  = "routing"
  peers = local.nb_peers.routing
}

# one resource-only group per target: peers and resources in one group hit provider bug #268
resource "netbird_group" "res_edge" {
  name = "res-edge"
}

resource "netbird_group" "res_netbird" {
  name = "res-netbird"
}

resource "netbird_group" "res_lan" {
  name = "res-lan"
}

resource "netbird_network" "lan" {
  name        = "lan"
  description = "the home lan, routed through pod-2"
}

resource "netbird_network_router" "lan" {
  network_id  = netbird_network.lan.id
  peer_groups = [netbird_group.routing.id]
  masquerade  = true
  metric      = 9999   # netbird's default
  enabled     = true
}

resource "netbird_network_resource" "edge" {
  network_id  = netbird_network.lan.id
  name        = "edge"
  description = "traefik, the web apps"
  address     = "${local.net.edge_ip}/32"
  groups      = [netbird_group.res_edge.id]
  enabled     = true
}

# no policy reaches it yet, kept so household -> netbird can be added
resource "netbird_network_resource" "netbird" {
  network_id  = netbird_network.lan.id
  name        = "netbird"
  description = "the netbird vm"
  address     = "${local.net.netbird_ip}/32"
  groups      = [netbird_group.res_netbird.id]
  enabled     = true
}

resource "netbird_network_resource" "lan" {
  network_id  = netbird_network.lan.id
  name        = "lan"
  description = "the whole lan, admins only"
  address     = local.net.lan_cidr
  groups      = [netbird_group.res_lan.id]
  enabled     = true
}

# one group per side in every rule: list order in state is the provider's bug #236
resource "netbird_policy" "admin_lan" {
  name    = "admin-lan"
  enabled = true
  rule {
    name          = "admin-lan"
    action        = "accept"
    bidirectional = false
    enabled       = true
    protocol      = "all"
    sources       = [netbird_group.admin.id]
    destinations  = [netbird_group.res_lan.id]
  }
}

resource "netbird_posture_check" "household_client" {
  name        = "household-client-version"
  description = "oldest client a household device may use"
  netbird_version_check {
    min_version = var.netbird_min_client_version
  }
}

resource "netbird_policy" "household_web" {
  name                  = "household-web"
  enabled               = true
  source_posture_checks = [netbird_posture_check.household_client.id]
  rule {
    name          = "household-web"
    action        = "accept"
    bidirectional = false
    enabled       = true
    protocol      = "tcp"
    ports         = [tostring(local.ports.https_port)]
    sources       = [netbird_group.household.id]
    destinations  = [netbird_group.res_edge.id]
  }
}

# dns relay on pod-2's overlay ip. split per source group: the posture check is per policy
resource "netbird_policy" "vpn_dns_admin" {
  name    = "vpn-dns-admin"
  enabled = true
  dynamic "rule" {
    for_each = ["udp", "tcp"]
    content {
      name          = "dns-${rule.value}"
      action        = "accept"
      bidirectional = false
      enabled       = true
      protocol      = rule.value
      ports         = [tostring(local.dns_relay_port)]
      sources       = [netbird_group.admin.id]
      destinations  = [netbird_group.routing.id]
    }
  }
}

resource "netbird_policy" "vpn_dns_household" {
  name                  = "vpn-dns-household"
  enabled               = true
  source_posture_checks = [netbird_posture_check.household_client.id]
  dynamic "rule" {
    for_each = ["udp", "tcp"]
    content {
      name          = "dns-${rule.value}"
      action        = "accept"
      bidirectional = false
      enabled       = true
      protocol      = rule.value
      ports         = [tostring(local.dns_relay_port)]
      sources       = [netbird_group.household.id]
      destinations  = [netbird_group.routing.id]
    }
  }
}

# netbird's built-in all-to-all policy, off: it would let every peer reach every peer.
# it exists from the first start, so import it before the first apply:
#   tofu import netbird_policy.default <policy id of "Default">
data "netbird_group" "all" {
  name = "All"
}

resource "netbird_policy" "default" {
  name        = "Default"
  description = "This is a default rule that allows connections between all the resources"
  enabled     = false
  rule {
    name          = "Default"
    description   = "This is a default rule that allows connections between all the resources"
    action        = "accept"
    bidirectional = true
    enabled       = true
    protocol      = "all"
    sources       = [data.netbird_group.all.id]
    destinations  = [data.netbird_group.all.id]
  }
}

# the peer exists only once pod-2 is enrolled (stage 2). name = its hostname (the "pod-2" key in locals.tf vms)
data "netbird_peer" "pod2" {
  name = "pod-2"
}

resource "netbird_nameserver_group" "lab" {
  name        = "lab"
  description = "dns-relay on pod-2, answers the lab domain"
  nameservers = [{
    ip      = data.netbird_peer.pod2.ip
    ns_type = "udp"
    port    = local.dns_relay_port
  }]
  domains                = [local.domain]
  primary                = false
  search_domains_enabled = false
  enabled                = true
  groups                 = [netbird_group.admin.id, netbird_group.household.id]
}

# routing peers keep port 53 for themselves
resource "netbird_dns_settings" "this" {
  disabled_management_groups = [netbird_group.routing.id]
}

# one one-off key per peer group, enrolled peers land in it.
# a new device = a targeted apply that makes a fresh key (-replace the old one)
resource "netbird_setup_key" "this" {
  for_each       = local.nb_peer_groups
  name           = each.key
  type           = "one-off"
  expiry_seconds = var.netbird_setup_key_expiry_seconds
  auto_groups    = [each.value]
}

output "netbird_setup_keys" {
  description = "plaintext setup keys by group: tofu output -json netbird_setup_keys"
  sensitive   = true
  value       = { for k, v in netbird_setup_key.this : k => v.key }
}
