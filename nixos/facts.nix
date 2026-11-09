# shared facts: ansible/group_vars/all/*.yml as one attrset, converted to json at build time.
# same source ansible and tofu read, so the nixos vms can't drift from the rest.
# private = the flake input holding private.yml (per-lab values).
{ pkgs, private }:
let
  inherit (pkgs) lib;
  groupVars = ../ansible/group_vars/all;
  toJson = name: file: builtins.fromJSON (builtins.readFile (pkgs.runCommand "${name}.json"
    { nativeBuildInputs = [ pkgs.yq-go ]; }
    "yq -o=json ${file} > $out"));
  read = name: toJson name "${groupVars}/${name}.yml";

  # the example only when the input has no private.yml (ci, flake check)
  privateFile =
    if builtins.pathExists "${private}/private.yml"
    then "${private}/private.yml" else "${private}/private.yml.example";

  vars = read "network" // read "ports" // read "hosts" // read "app_settings" // read "apps" // read "base" // read "schedules"
    // toJson "private" privateFile;

  # inventory host -> ip. ansible_host is "{{ <var> }}", the var is looked up in the facts above.
  # group-only entries (netbird_agent's pod-2: null) carry no ansible_host and are skipped
  inventoryHosts = node:
    lib.filterAttrs (_: h: builtins.isAttrs h && h ? ansible_host) (node.hosts or { })
    // lib.foldl' (acc: c: acc // inventoryHosts c) { } (lib.attrValues (node.children or { }));
  resolve = name: h:
    let m = builtins.match "[{][{] *([a-z0-9_]+) *[}][}]" (h.ansible_host or "");
    in if m == null then throw "inventory: ${name} has no {{ var }} ansible_host" else vars.${lib.head m};
  hostIps = lib.mapAttrs resolve (inventoryHosts (toJson "inventory" ../ansible/inventory.yml).all);
in
vars // { private_file = privateFile; host_ips = hostIps; }
