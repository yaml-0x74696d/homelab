# shared facts: ansible/group_vars/all/*.yml as one attrset, converted to json at build time.
# same source ansible and tofu read, so the netbird box can't drift from the rest.
# private = the flake input holding private.yml (per-lab values).
{ pkgs, private }:
let
  groupVars = ../ansible/group_vars/all;
  toJson = name: file: builtins.fromJSON (builtins.readFile (pkgs.runCommand "${name}.json"
    { nativeBuildInputs = [ pkgs.yq-go ]; }
    "yq -o=json ${file} > $out"));
  read = name: toJson name "${groupVars}/${name}.yml";

  # the example only when the input has no private.yml (ci, flake check)
  privateFile =
    if builtins.pathExists "${private}/private.yml"
    then "${private}/private.yml" else "${private}/private.yml.example";
in
read "network" // read "ports" // read "hosts" // read "apps"
// toJson "private" privateFile // { private_file = privateFile; }
