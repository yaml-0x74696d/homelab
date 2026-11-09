# riced fastfetch on login, to match the debian vms' greeter
{ pkgs, ... }:
let
  fastfetchConfig = pkgs.writeText "fastfetch.jsonc" ''
    {
      "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
      "logo": { "source": "nixos", "padding": { "top": 1, "left": 2 } },
      "display": { "separator": "  " },
      "modules": [
        "title",
        "separator",
        { "type": "os",       "key": "  OS      " },
        { "type": "kernel",   "key": "  Kernel  " },
        { "type": "uptime",   "key": "  Uptime  " },
        { "type": "packages", "key": "  Packages" },
        { "type": "memory",   "key": "  Memory  " },
        { "type": "disk",     "key": "  Disk    ", "folders": "/" },
        { "type": "localip",  "key": "  IP      ", "showIpv6": false },
        "break",
        "colors"
      ]
    }
  '';
in
{
  environment.systemPackages = [ pkgs.fastfetch ];

  # once per interactive login shell (ssh / console), not nested shells
  programs.bash.loginShellInit = ''
    if [[ $- == *i* ]]; then
      ${pkgs.fastfetch}/bin/fastfetch --config ${fastfetchConfig}
    fi
  '';
}
