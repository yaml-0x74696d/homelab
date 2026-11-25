# netbird self-hosted control plane (native, no docker) via the nixpkgs server module.
# tls: nginx + acme dns-01 (cloudflare). idp: authentik. stun/turn: coturn.
#
# secrets not in git: the module reads them from files under ${secretsDir}, create them
# before the first switch. clientId isn't secret, it comes from private.yml (netbird_oidc_client_id).
{ facts, ... }:
let
  domain = "nb.${facts.domain}";
  authAppSlug = "netbird";
  authAuthority = "https://auth.${facts.domain}/application/o/${authAppSlug}/";
  # authentik makes the token audience == the client id (public client, not a secret).
  clientId = facts.netbird_oidc_client_id;
  scopes = "openid profile email offline_access api";
  secretsDir = "/var/lib/secrets/netbird";

  acmeEmail = "admin@${facts.domain}";   # le expiry notices
  acmeResolver = "1.1.1.1:53";            # validate against public dns
  mgmtRestartSec = 15;

  lanCidr = facts.lan_cidr;   # vpn peers arrive snat'd from the routing peer, so this covers them too
  # wan hits on the dashboard/api before a ban (bantime comes from hardening.nix)
  probeMaxRetry = 5;
  probeFindTime = "10m";
  # wan only needs the grpc paths; everything else gets a silent close
  lanOnly = ''
    if ($from_lan = 0) { return 444; }
  '';
in
{
  services.netbird.server = {
    enable = true;
    inherit domain;
    enableNginx = true;   # localhost mgmt/signal/dashboard vhosts on ${domain}

    management = {
      oidcConfigEndpoint = "${authAuthority}.well-known/openid-configuration";
      settings = {
        # never ship the module's placeholder key on a wan box
        DataStoreEncryptionKey._secret = "${secretsDir}/datastore-key";

        HttpConfig = {
          AuthIssuer = authAuthority;
          AuthAudience = clientId;   # authentik: audience == client id
        };

        # cli / device login
        DeviceAuthorizationFlow = {
          Provider = "hosted";
          ProviderConfig = {
            Audience = clientId;
            ClientID = clientId;
            Scope = scopes;
          };
        };
        # browser / pkce login
        PKCEAuthorizationFlow.ProviderConfig = {
          Audience = clientId;
          ClientID = clientId;
          Scope = scopes;
          RedirectURLs = [ "http://localhost:53000" ];
          DisablePromptLogin = true;   # authentik workaround (netbird #3654)
        };
        # user/group sync off: the idp-manager client_credentials call to authentik's token
        # endpoint 405'd and broke login. oidc login still works, only bulk user/group listing is gone;
        # re-enable needs /application/o/token/ + a client-credentials service account in authentik
        IdpManagerConfig = {
          ManagerType = "none";
          ClientConfig = {
            Issuer = authAuthority;
            ClientID = clientId;
            TokenEndpoint = "${authAuthority}token/";
            GrantType = "client_credentials";
          };
          ExtraConfig = {
            Username = "netbird-svc";
            Password._secret = "${secretsDir}/idp-svc-password";
          };
        };

        # silence the module's insecure-default warning (unused with long-term turn creds)
        TURNConfig.Secret._secret = "${secretsDir}/turn-secret";
      };
    };

    coturn = {
      enable = true;
      inherit domain;
      passwordFile = "${secretsDir}/turn-password";   # long-term cred, auto-synced into mgmt
      useAcmeCertificates = true;                      # turns:5349 reuses the nginx cert
    };

    dashboard.settings = {
      AUTH_AUTHORITY = authAuthority;
      AUTH_CLIENT_ID = clientId;
      AUTH_AUDIENCE = clientId;
      AUTH_SUPPORTED_SCOPES = scopes;
      USE_AUTH0 = false;
      NETBIRD_TOKEN_SOURCE = "idToken";
      AUTH_REDIRECT_URI = "/auth";
      AUTH_SILENT_REDIRECT_URI = "/silent-auth";
    };
  };

  # keep the coturn relay range small so the router forward is a narrow block
  services.coturn = {
    min-port = facts.netbird_relay_ports.min;
    max-port = facts.netbird_relay_ports.max;
  };

  # one public web port; the coturn module opens its own (3478/5349 + relay range)
  networking.firewall.allowedTCPPorts = [ 443 ];

  # acme dns-01 via cloudflare, no http-01, no port 80. reuses the ddns CF token.
  security.acme = {
    acceptTerms = true;
    defaults.email = acmeEmail;
    certs.${domain} = {
      dnsProvider = "cloudflare";
      group = "nginx";                                     # nginx must read the cert (useACMEHost)
      environmentFile = "${secretsDir}/cloudflare.env";   # CF_DNS_API_TOKEN=...
      dnsResolver = acmeResolver;
    };
  };
  services.nginx.virtualHosts.${domain} = {
    useACMEHost = domain;   # use our dns-01 cert, not http-01/webroot
    forceSSL = true;
    locations."/".extraConfig = lanOnly;
    locations."/api".extraConfig = lanOnly;
  };
  services.nginx.appendHttpConfig = ''
    geo $from_lan {
      default 0;
      ${lanCidr} 1;
    }
  '';

  # ban wan ips that keep poking the lan-only paths (the 444s above)
  services.fail2ban.jails.nginx-lan-only = {
    filter.Definition.failregex = ''^<HOST> \S+ \S+ \[[^]]*\] "[^"]*" 444 '';
    settings = {
      logpath = "/var/log/nginx/access.log";
      backend = "auto";
      port = "https";
      maxretry = probeMaxRetry;
      findtime = probeFindTime;
    };
  };

  # no extra SystemCallFilter on mgmt/signal, it SIGSYS-kills netbird-mgmt on the oidc https call

  # mgmt dies if authentik is unreachable at start; retry instead of giving up
  systemd.services.netbird-management = {
    unitConfig.StartLimitIntervalSec = 0;
    serviceConfig.RestartSec = mgmtRestartSec;
  };
}
