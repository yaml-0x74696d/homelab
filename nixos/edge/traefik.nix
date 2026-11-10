# traefik for every *.<domain> route. routers come from apps.yml (apps.*.routes + infra_routes,
# via facts.nix), middlewares live here. one wildcard cert via acme dns-01 (cloudflare).
# the dynamic config is a real file under /etc that traefik watches: a route change is a
# nixos-rebuild, no traefik restart.
#
# secret NOT in git: ${secretsDir}/cloudflare.env (CF_DNS_API_TOKEN=...), create before the first switch.
{ config, lib, pkgs, facts, ... }:
let
  inherit (facts) domain;
  secretsDir = "/var/lib/secrets/edge";

  acmeEmail = "admin@${domain}";                    # le expiry notices
  acmeResolvers = [ "1.1.1.1:53" "8.8.8.8:53" ];   # public: adguard answers the zone locally
  logLevel = "INFO";

  dynamicFile = "/etc/traefik/dynamic.yml";
  yaml = pkgs.formats.yaml { };

  authentikPath = "/outpost.goauthentik.io/auth/traefik";
  authentik = facts.apps.authentik;

  # what edge serves itself (infra_routes with target: edge), by route host
  localServices = {
    traefik = "api@internal";
    dns = "adguard";
  };
  adguardUrl = "http://${config.services.adguardhome.settings.http.address}";

  ipOf = host: facts.host_ips.${host} or (throw "edge: ${host} isn't in the inventory");
  rule = r: "Host(`${r.host}.${domain}`)" + lib.optionalString (r ? path) " && PathPrefix(`${r.path}`)";

  # apps.*.routes -> { id, route, service, backend? }. ids: <app>, <app>-1, ... in route order
  present = lib.filterAttrs (_: a: (a.state or "present") == "present") facts.apps;
  appRoutes = lib.concatLists (lib.mapAttrsToList (name: a:
    lib.imap0 (i: r: rec {
      id = if i == 0 then name else "${name}-${toString i}";
      route = r;
      service = id;
      backend = { url = "http://${ipOf a.host}:${toString (r.port or a.port)}"; insecure = false; };
    }) (a.routes or [ ])) present);

  # infra_routes with a target; the rest is pod-1's traefik only
  infraRoutes = map (r: rec {
    id = r.host;
    route = r;
    service = if r.target == "edge" then localServices.${r.host} else id;
    backend = lib.optionalAttrs (r.target != "edge") {
      url = "${r.scheme or "http"}://${ipOf r.target}:${toString facts.${r.port_var}}";
      insecure = r.insecure_tls or false;
    };
  }) (lib.filter (r: r ? target) facts.infra_routes);

  routes = appRoutes ++ infraRoutes;
  withBackend = lib.filter (x: x.backend != { }) routes;

  dynamic = {
    http = {
      routers = lib.listToAttrs (map (x: lib.nameValuePair x.id ({
        rule = rule x.route;
        entryPoints = [ "websecure" ];
        inherit (x) service;
      } // lib.optionalAttrs ((x.route.middlewares or [ ]) != [ ]) {
        inherit (x.route) middlewares;
      })) routes);

      services = lib.listToAttrs (map (x: lib.nameValuePair x.id {
        loadBalancer = {
          servers = [ { inherit (x.backend) url; } ];
        } // lib.optionalAttrs x.backend.insecure { serversTransport = "insecure"; };
      }) withBackend) // {
        adguard.loadBalancer.servers = [ { url = adguardUrl; } ];
      };

      # pve + pbs use self-signed certs
      serversTransports.insecure.insecureSkipVerify = true;

      middlewares = {
        # authentik forward-auth, domain level: needs a proxy provider (forward auth, domain level)
        # on the embedded outpost. the cookie is good for the whole zone
        authentik.forwardAuth = {
          address = "http://${ipOf authentik.host}:${toString authentik.port}${authentikPath}";
          trustForwardHeader = true;
          authResponseHeaders = [
            "X-authentik-username"
            "X-authentik-groups"
            "X-authentik-email"
            "X-authentik-name"
            "X-authentik-uid"
            "X-authentik-jwt"
            "X-authentik-meta-jwks"
            "X-authentik-meta-outpost"
            "X-authentik-meta-provider"
            "X-authentik-meta-app"
            "X-authentik-meta-version"
          ];
        };
        # dav discovery: /.well-known/{card,cal}dav -> /remote.php/dav
        nextcloud-dav.redirectRegex = {
          regex = "https://(.*)/.well-known/(card|cal)dav";
          replacement = "https://\${1}/remote.php/dav";
          permanent = true;
        };
      };
    };
  };
  usedMiddlewares = lib.unique (lib.concatMap (x: x.route.middlewares or [ ]) routes);
  missing = lib.subtractLists (lib.attrNames dynamic.http.middlewares) usedMiddlewares;
in
{
  # a typo in apps.yml fails the build, not a route at runtime
  assertions = [ {
    assertion = missing == [ ];
    message = "edge: apps.yml uses middlewares traefik.nix doesn't define: ${toString missing}";
  } ];

  services.traefik = {
    enable = true;
    dynamicConfigFile = dynamicFile;
    environmentFiles = [ "${secretsDir}/cloudflare.env" ];
    staticConfigOptions = {
      log.level = logLevel;
      accessLog = { };   # stdout -> journal -> rsyslog
      api.dashboard = true;
      providers.file.watch = true;

      entryPoints = {
        web = {
          address = ":80";
          http.redirections.entryPoint = { to = "websecure"; scheme = "https"; };
        };
        websecure = {
          address = ":443";
          # every router on 443 shares the one wildcard cert
          http.tls = {
            certResolver = "cloudflare";
            domains = [ { main = domain; sans = [ "*.${domain}" ]; } ];
          };
        };
      };

      certificatesResolvers.cloudflare.acme = {
        email = acmeEmail;
        storage = "${config.services.traefik.dataDir}/acme.json";
        dnsChallenge = {
          provider = "cloudflare";
          resolvers = acmeResolvers;
        };
      };
    };
  };

  # a copied file, not a store symlink: the switch replaces it in place, so traefik's watch fires
  environment.etc."traefik/dynamic.yml" = {
    source = yaml.generate "traefik-dynamic.yml" dynamic;
    mode = "0444";
  };

  # lan + vpn peers (they arrive from the routing peer's lan ip)
  networking.firewall.extraInputRules = ''
    ip saddr ${facts.lan_cidr} tcp dport { 80, 443 } accept
  '';
}
