# node_exporter for prometheus, like the debian guests. only prometheus' host may scrape it
{ facts, ... }:
let
  prometheusIp = facts.host_ips.${facts.apps.prometheus.host};
in
{
  services.prometheus.exporters.node = {
    enable = true;
    port = facts.node_exporter_port;
    openFirewall = false;   # the default would open it to every source
  };
  networking.firewall.extraInputRules = ''
    ip saddr ${prometheusIp} tcp dport ${toString facts.node_exporter_port} accept
  '';
}
