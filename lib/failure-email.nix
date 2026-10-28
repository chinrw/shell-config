let
  mkModule =
    userService:
    {
      lib,
      pkgs,
      ...
    }:
    let
      sender = pkgs.writeShellApplication {
        name = "failure-email";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.curl
          pkgs.python3
          pkgs.systemd
        ];
        text = ''
          scope="$1"
          unit="$2"
          case "$scope" in
            system|user) ;;
            *) echo 'Expected system or user service scope' >&2; exit 1 ;;
          esac

          umask 077
          message=$(mktemp)
          trap 'rm -f "$message"' EXIT
          python3 - "$scope" "$unit" >"$message" <<'PY'
          import json
          import os
          import re
          import shlex
          import socket
          import subprocess
          import sys
          from datetime import datetime, timedelta, timezone

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
                  "start-limit-hit": "The service kept failing and systemd stopped retrying it",
                  "resources": "The service could not start because setup or resource allocation failed",
              }.get(result, f"The service reported an unexpected result: {result}")
              if status and result == "exit-code":
                  reason += f" (exit code {status})"
              elif status and result in ("signal", "core-dump"):
                  reason += f" ({status})"
              elif status and result == "start-limit-hit":
                  reason += f" (last exit status {status})"
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
              if unit == "shell-config-updater.service":
                  invocation = os.environ.get("MONITOR_INVOCATION_ID", "")
                  logs = "Logs unavailable: the failed invocation ID was not provided."
                  if re.fullmatch(r"[0-9a-f]{32}", invocation):
                      # Match the failed run, not a later timer run or restart.
                      command += [f"_SYSTEMD_INVOCATION_ID={invocation}", "--output=cat", "--quiet"]
                      try:
                          completed = subprocess.run(
                              command, capture_output=True, text=True, errors="replace",
                              check=True, timeout=10,
                          )
                          logs = completed.stdout.strip() or "No journal entries were found for the failed run."
                      except (OSError, subprocess.SubprocessError):
                          logs = "Logs unavailable: reading the failed invocation's journal failed."
                  # Redact common credential formats before adding journal output to email.
                  logs = re.sub(
                      r"(?im)^.*\b(?:authorization|cookie|[\w-]*(?:password|passwd|token|secret|api[_-]?key)[\w-]*)\b[\"']?\s*[:=].*$",
                      "[REDACTED: credential-bearing log line]", logs,
                  )
                  logs = re.sub(r"\b(?:github_pat_|gh[pousr]_)[A-Za-z0-9_]+", "[REDACTED]", logs)
                  logs = re.sub(r"(\w+://)[^/\s@]+@", r"\1[REDACTED]@", logs)
                  logs = re.sub(r"(https?://[^\s?#]+)\?[^\s]*", r"\1?[REDACTED]", logs)
                  logs = logs.encode("utf-8")
                  if len(logs) > 12000:
                      logs = b"[Earlier log output truncated]\n" + logs[-11950:]
                  body += (
                      "\nFailed run's journal (last 50 entries; common credentials redacted):\n\n"
                      f"{logs.decode('utf-8', errors='replace')}\n"
                  )

          json.dump({"topic": "alerts", "title": subject, "message": body}, sys.stdout, ensure_ascii=False)
          PY

          curl --disable --silent --show-error --fail-with-body \
            --noproxy '*' --url http://192.168.0.241:9080/ \
            --json "@$message" \
            --connect-timeout 15 --max-time 70 \
            --retry 2 --retry-connrefused --retry-delay 30
        '';
      };
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lib.getExe sender} ${if userService then "user" else "system"} %i";
        TimeoutStartSec = "5min";
        UMask = "0077";
        NoNewPrivileges = true;
      };
    in
    {
      # Several task modules can import the same notifier without duplicating it.
      key = "shell-config.failure-email.${if userService then "home-manager" else "nixos"}";
    }
    // (
      if userService then
        {
          systemd.user.services."email-failure@" = {
            Unit = {
              Description = "Email failure notification for %i";
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
