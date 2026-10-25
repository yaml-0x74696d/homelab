# shared facts: ansible/group_vars/all/*.yml as one attrset, converted to json at build time.
# same source ansible and tofu read, so the netbird box can't drift from the rest.
{ pkgs }:
let
  groupVars = ../ansible/group_vars/all;
  read = name: builtins.fromJSON (builtins.readFile (pkgs.runCommand "${name}.json"
    { nativeBuildInputs = [ pkgs.yq-go ]; }
    "yq -o=json ${groupVars}/${name}.yml > $out"));
in
read "network" // read "ports" // read "hosts" // read "apps"
