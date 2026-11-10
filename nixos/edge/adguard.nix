# adguard home: lan dns + blocking. config only from here (mutableSettings = false), ui changes
# are gone after a restart. split horizon: every routed host -> edge, nb -> the netbird vm.
# ui on localhost, traefik serves it as dns.<domain> behind authentik; no adguard login.
# break-glass: ssh -L 3000:127.0.0.1:3000 to edge (users would land in the world-readable store)
{ lib, facts, ... }:
let
  inherit (facts) domain;
  holdsDnsIp = facts.dns_ip_host == "edge";

  uiAddress = "127.0.0.1:3000";
  queryLogRetention = "168h";   # 7 days

  # encrypted upstreams only: quad9 + cloudflare, dot and doh
  upstreams = [
    "tls://dns.quad9.net"
    "https://dns.quad9.net/dns-query"
    "tls://one.one.one.one"
    "https://cloudflare-dns.com/dns-query"
  ];
  # plain ips that resolve the upstream names
  bootstrap = [ "9.9.9.9" "149.112.112.112" "1.1.1.1" "1.0.0.1" ];

  blocklist = {
    name = "AdGuard DNS filter";
    url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt";
  };

  netbirdHost = "nb";   # netbird.nix serves nb.<domain> itself, not behind traefik

  # every host traefik serves here (apps.yml routes + infra_routes with a target)
  present = lib.filterAttrs (_: a: (a.state or "present") == "present") facts.apps;
  routedHosts = lib.unique (
    lib.concatMap (a: map (r: r.host) (a.routes or [ ])) (lib.attrValues present)
    ++ map (r: r.host) (lib.filter (r: r ? target) facts.infra_routes));
  rewrite = host: answer: { domain = "${host}.${domain}"; inherit answer; enabled = true; };
in
{
  services.adguardhome = {
    enable = true;
    mutableSettings = false;
    settings = {
      http.address = uiAddress;
      users = [ ];

      dns = {
        # specific ips, so the resolved stub on 127.0.0.53 keeps its port
        bind_hosts = [ facts.edge_ip ] ++ lib.optional holdsDnsIp facts.dns_ip;
        port = 53;
        upstream_dns = upstreams;
        bootstrap_dns = bootstrap;
      };

      filtering.rewrites = map (h: rewrite h facts.edge_ip) routedHosts
        ++ [ (rewrite netbirdHost facts.netbird_ip) ];

      filters = [ (blocklist // { enabled = true; id = 1; }) ];
      whitelist_filters = [ ];

      querylog = {
        enabled = true;
        interval = queryLogRetention;
      };
    };
  };

  # the second address (dns_ip) may come up after network.target
  systemd.services.adguardhome = {
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
  };

  networking.firewall.extraInputRules = ''
    ip saddr ${facts.lan_cidr} meta l4proto { tcp, udp } th dport 53 accept
  '';
}
