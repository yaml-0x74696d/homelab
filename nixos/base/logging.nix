# volatile journal, rsyslog files + relp to the log lxc, like roles/journald + roles/rsyslog.
# rsyslog gets the journal over the syslog socket (the module's imuxsock), not imjournal
{ config, facts, ... }:
let
  localFiles = [ "/var/log/messages" "/var/log/secure" "/var/log/boot.log" ];
in
{
  services.journald.settings.Journal = {
    Storage = facts.journald_storage;
    RuntimeMaxUse = facts.journald_runtime_max_use;
    RateLimitIntervalSec = facts.journald_rate_limit_interval;
    RateLimitBurst = facts.journald_rate_limit_burst;
    Compress = true;
  };

  services.rsyslogd = {
    enable = true;
    # rhel layout like the debian guests; no cron/mail here
    defaultConfig = ''
      module(load="builtin:omfile" Template="RSYSLOG_TraditionalFileFormat" fileCreateMode="0640")

      *.info;mail.none;auth,authpriv.none;cron.none   /var/log/messages
      auth,authpriv.*                                 /var/log/secure
      local7.*                                        /var/log/boot.log
      *.emerg                                         :omusrmsg:*
    '';
    # everything to the log lxc, acked per message; the queue spills to /var/spool/rsyslog
    extraConfig = ''
      module(load="omrelp")
      action(type="omrelp"
             target="${facts.log_ip}"
             port="${toString facts.log_relp_port}"
             template="RSYSLOG_ForwardFormat"
             queue.type="LinkedList"
             queue.filename="forward"
             queue.maxDiskSpace="${facts.rsyslog_queue_max_disk}"
             queue.saveOnShutdown="on"
             action.resumeRetryCount="-1"
             action.resumeInterval="${toString facts.rsyslog_resume_interval}")
    '';
  };

  services.logrotate.settings.rsyslog = {
    files = localFiles;
    frequency = "weekly";
    rotate = facts.rsyslog_local_rotate;
    missingok = true;
    notifempty = true;
    compress = true;
    delaycompress = true;
    sharedscripts = true;
    postrotate = "${config.systemd.package}/bin/systemctl kill -s HUP syslog.service";
  };
}
