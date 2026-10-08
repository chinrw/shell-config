let
  mkModule =
    userService:
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      address = "chinqrw@gmail.com";
      sender = pkgs.writeShellApplication {
        name = "failure-email";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.curl
          pkgs.python3
        ];
        text = ''
          scope="$1"
          unit="$2"
          case "$scope" in
            system|user) ;;
            *) echo 'Expected system or user service scope' >&2; exit 1 ;;
          esac

          password=$(tr -d '[:space:]' <"$CREDENTIALS_DIRECTORY/smtp-password")
          if [[ ! "$password" =~ ^[a-zA-Z0-9]{16}$ ]]; then
            echo 'Expected a 16-character Google app password' >&2
            exit 1
          fi

          umask 077
          message=$(mktemp)
          trap 'rm -f "$message"' EXIT
          python3 - "$scope" "$unit" >"$message" <<'PY'
          import os
          import shlex
          import socket
          import sys
          from datetime import datetime, timedelta, timezone
          from email.message import EmailMessage
          from email.policy import SMTP
          from email.utils import format_datetime, make_msgid

          scope, unit = sys.argv[1:]
          host = socket.gethostname()
          now = datetime.now(timezone(timedelta(hours=8)))
          task = {
              "shell-config-updater.service": "Shell-config update",
              "restic-backups-vm-nix.service": "Restic backup",
          }.get(unit, unit)
          # Preserve the failed invocation's result. The unit may already have restarted.
          result = os.environ.get("MONITOR_SERVICE_RESULT")
          status = os.environ.get("MONITOR_EXIT_STATUS")
          is_test = result in (None, "manual-email-test")
          details = f"Host: {host}\nNotified: {now:%Y-%m-%d %H:%M:%S} UTC+08:00"

          if is_test:
              subject = f"[Test] Email notifications from {host}"
              body = (
                  "This is a test of your task failure notifications.\n"
                  "No backup or update job was started, and no action is needed.\n\n"
                  f"{details}\n\n"
                  "Receiving this message confirms that email delivery is working.\n"
              )
          else:
              reason = {
                  "exit-code": "The process exited with an error",
                  "signal": "The process was terminated by a signal",
                  "core-dump": "The process crashed and dumped core",
                  "timeout": "The task exceeded its time limit",
                  "watchdog": "The task stopped responding to watchdog checks",
                  "oom-kill": "The system ran out of memory and terminated the process",
                  "start-limit-hit": "Too many start attempts; further starts were blocked",
                  "resources": "The service could not start because setup or resource allocation failed",
              }.get(result, f"The service reported an unexpected result: {result}")
              if status and result == "exit-code":
                  reason += f" (exit code {status})"
              elif status and result in ("signal", "core-dump"):
                  reason += f" ({status})"
              command = ["journalctl"]
              if scope == "user":
                  command.append("--user")
              command += ["-u", unit, "-n", "50", "--no-pager"]
              subject = f"[Failed] {task} on {host}"
              body = (
                  f"{task} failed on {host}.\n\n"
                  f"Reason: {reason}\n{details}\nService: {unit}\n\n"
                  f"To investigate, sign in to {host} and check the latest logs:\n\n"
                  f"  {shlex.join(command)}\n"
              )

          message = EmailMessage(policy=SMTP)
          message["From"] = ${builtins.toJSON address}
          message["To"] = ${builtins.toJSON address}
          message["Subject"] = subject
          message["Date"] = format_datetime(now)
          message["Message-ID"] = make_msgid(domain=host)
          message.set_content(body, cte="base64")
          sys.stdout.buffer.write(message.as_bytes())
          PY

          # Read authentication through a file descriptor so it stays out of argv.
          # SMTP needs an explicit HTTP CONNECT tunnel through the LAN proxy.
          curl --disable --silent --show-error \
            --config <(printf 'user = "%s:%s"\n' ${lib.escapeShellArg address} "$password") \
            --url smtp://smtp.gmail.com:587 --ssl-reqd \
            --cacert ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt \
            --proxy http://192.168.0.240:10809 --proxytunnel \
            --mail-from ${lib.escapeShellArg address} --mail-rcpt ${lib.escapeShellArg address} \
            --upload-file "$message" \
            --connect-timeout 15 --max-time 60 \
            --retry 2 --retry-all-errors --retry-delay 30
        '';
      };
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lib.getExe sender} ${if userService then "user" else "system"} %i";
        LoadCredential = "smtp-password:${config.sops.secrets."email/smtp-password".path}";
        TimeoutStartSec = "5min";
        UMask = "0077";
        NoNewPrivileges = true;
      };
    in
    {
      # Several task modules can import the same notifier without duplicating it.
      key = "shell-config.failure-email.${if userService then "home-manager" else "nixos"}";
      sops.secrets."email/smtp-password" = {
        sopsFile = ../secrets/email.yaml;
        key = "smtp-password";
      };
    }
    // (
      if userService then
        {
          systemd.user.services."email-failure@" = {
            Unit = {
              Description = "Email failure notification for %i";
              Requires = [ "sops-nix.service" ];
              After = [ "sops-nix.service" ];
            };
            Service = serviceConfig;
          };
        }
      else
        {
          systemd.services."email-failure@" = {
            description = "Email failure notification for %i";
            wants = [ "network-online.target" ];
            after = [ "network-online.target" ];
            serviceConfig = serviceConfig // {
              PrivateTmp = true;
              ProtectSystem = "strict";
              ProtectHome = true;
            };
          };
        }
    );
in
{
  nixos = mkModule false;
  homeManager = mkModule true;
}
