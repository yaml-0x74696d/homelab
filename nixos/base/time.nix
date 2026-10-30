# chrony with nts, same servers + step rules as the debian guests (group_vars/all/base.yml)
{ facts, ... }:
{
  services.chrony = {
    enable = true;   # turns timesyncd off
    servers = facts.chrony_servers;
    enableNTS = true;
    makestep = {
      threshold = facts.chrony_makestep_threshold;
      limit = facts.chrony_makestep_limit;
    };
  };
}
