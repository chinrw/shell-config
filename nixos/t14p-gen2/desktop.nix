{
  config,
  lib,
  pkgs,
  ...
}:
let
  allowedFingerprintPamServices = [
    "kde-fingerprint"
    "login"
  ];
  enabledFingerprintPamServices = lib.sort builtins.lessThan (
    builtins.attrNames (
      lib.filterAttrs (
        _: service: service.rules.auth.fprintd.enable or false
      ) config.security.pam.services
    )
  );
  niriPackage = config.programs.niri.package;
  hyprlockConfig = "/etc/t14p/hyprlock.conf";
  hyprlockCommand = lib.escapeShellArgs [
    (lib.getExe pkgs.hyprlock)
    "--config"
    hyprlockConfig
  ];
  tuigreetCommand = lib.escapeShellArgs [
    (lib.getExe pkgs.tuigreet)
    "--time"
    "--user-menu"
    "--remember"
    "--remember-user-session"
    "--cmd"
    (lib.getExe' niriPackage "niri-session")
    "--sessions"
    "${config.services.displayManager.sessionData.desktops}/share/wayland-sessions"
  ];
  lockBeforeSleep = pkgs.writeShellApplication {
    name = "t14p-lock-before-sleep";
    runtimeInputs = with pkgs; [
      coreutils
      gawk
      systemd
    ];
    text = ''
      set -euo pipefail

      loginctl list-sessions --no-legend | awk '{ print $1 }' | while read -r session; do
        [[ -n "$session" ]] || continue

        active=$(loginctl show-session "$session" --property Active --value 2>/dev/null || true)
        class=$(loginctl show-session "$session" --property Class --value 2>/dev/null || true)
        remote=$(loginctl show-session "$session" --property Remote --value 2>/dev/null || true)
        type=$(loginctl show-session "$session" --property Type --value 2>/dev/null || true)

        [[ "$active" == "yes" && "$class" == "user" && "$remote" == "no" ]] || continue
        [[ "$type" == "wayland" || "$type" == "x11" ]] || continue

        loginctl lock-session "$session" || continue

        locked=no
        for _ in {1..50}; do
          if [[ "$(loginctl show-session "$session" --property LockedHint --value 2>/dev/null)" == "yes" ]]; then
            locked=yes
            break
          fi
          sleep 0.1
        done

        if [[ "$locked" != "yes" ]]; then
          echo "warning: session $session did not report LockedHint=yes before sleep" >&2
        fi
      done
    '';
  };
in
{
  services = {
    desktopManager.plasma6.enable = true;

    displayManager.defaultSession = "niri";

    greetd = {
      enable = true;
      useTextGreeter = true;
      settings.default_session.command = tuigreetCommand;
    };

    fprintd.enable = true;
  };

  programs.niri.enable = true;

  security.pam.services = {
    # greetd delegates authentication to the login substack.
    login = {
      fprintAuth = true;
      rules.auth.fprintd.settings = {
        "max-tries" = 2;
        timeout = 5;
      };
    };

    # hyprlock uses fprintd over D-Bus in parallel with PAM password auth.
    hyprlock.fprintAuth = false;

    # Fingerprints unlock sessions; privilege elevation still needs a password.
    chfn.fprintAuth = false;
    chpasswd.fprintAuth = false;
    chsh.fprintAuth = false;
    groupadd.fprintAuth = false;
    groupdel.fprintAuth = false;
    groupmems.fprintAuth = false;
    groupmod.fprintAuth = false;
    i3lock.fprintAuth = false;
    i3lock-color.fprintAuth = false;
    passwd.fprintAuth = false;
    "polkit-1".fprintAuth = false;
    runuser.fprintAuth = false;
    runuser-l.fprintAuth = false;
    sshd.fprintAuth = false;
    sudo.fprintAuth = false;
    su.fprintAuth = false;
    swaylock.fprintAuth = false;
    systemd-run0.fprintAuth = false;
    systemd-user.fprintAuth = false;
    useradd.fprintAuth = false;
    userdel.fprintAuth = false;
    usermod.fprintAuth = false;
    vlock.fprintAuth = false;
    xlock.fprintAuth = false;
    xscreensaver.fprintAuth = false;
  };

  assertions = [
    {
      assertion = enabledFingerprintPamServices == allowedFingerprintPamServices;
      message = ''
        Unexpected PAM services have fingerprint authentication enabled.
        Expected ${builtins.toJSON allowedFingerprintPamServices}, got
        ${builtins.toJSON enabledFingerprintPamServices}.
      '';
    }
  ];

  environment = {
    systemPackages = with pkgs; [
      hypridle
      hyprlock
    ];

    etc = {
      "niri/config.kdl".text = ''
        include "${niriPackage.doc}/share/doc/niri/default-config.kdl"

        binds {
            Super+Alt+L allow-inhibiting=false allow-when-locked=true hotkey-overlay-title="Lock the Screen: hyprlock" {
                spawn "${lib.getExe pkgs.hyprlock}" "--config" "${hyprlockConfig}";
            }
        }
      '';

      "t14p/hyprlock.conf".text = ''
        general {
            hide_cursor = true
        }

        auth {
            pam {
                enabled = true
                module = hyprlock
            }
            fingerprint {
                enabled = true
                ready_message = Scan fingerprint or enter password
                present_message = Scanning fingerprint...
                retry_delay = 250
            }
        }

        background {
            monitor =
            color = rgb(1e1e2e)
        }

        input-field {
            monitor =
            size = 360, 64
            outline_thickness = 2
            rounding = 12
            outer_color = rgb(89b4fa)
            inner_color = rgb(181825)
            font_color = rgb(cdd6f4)
            placeholder_text = Password
            fail_text = $PAMFAIL$FPRINTFAIL
            position = 0, -40
            halign = center
            valign = center
        }

        label {
            monitor =
            text = $TIME
            font_size = 72
            color = rgb(cdd6f4)
            position = 0, 120
            halign = center
            valign = center
        }

        label {
            monitor =
            text = $FPRINTPROMPT
            font_size = 18
            color = rgb(a6adc8)
            position = 0, -120
            halign = center
            valign = center
        }
      '';

      "t14p/hypridle.conf".text = ''
        general {
            lock_cmd = ${lib.getExe' pkgs.procps "pidof"} hyprlock || ${hyprlockCommand}
            before_sleep_cmd = ${lib.getExe' pkgs.systemd "loginctl"} lock-session
        }

        listener {
            timeout = 300
            on-timeout = ${lib.getExe' pkgs.systemd "loginctl"} lock-session
        }

        listener {
            timeout = 330
            on-timeout = ${lib.getExe niriPackage} msg action power-off-monitors
            on-resume = ${lib.getExe niriPackage} msg action power-on-monitors
        }
      '';
    };
  };

  # Binding this unit to niri.service prevents it from competing with Plasma's
  # own idle and lock handling in the fallback Plasma session.
  systemd.user.services.niri-hypridle = {
    description = "Idle handling for the Niri session";
    wantedBy = [ "niri.service" ];
    partOf = [ "niri.service" ];
    after = [ "niri.service" ];
    serviceConfig = {
      ExecStart = "${lib.getExe pkgs.hypridle} --config /etc/t14p/hypridle.conf";
      Restart = "on-failure";
      RestartSec = 1;
    };
  };

  systemd.services.t14p-lock-before-sleep = {
    description = "Lock graphical sessions before sleep";
    requiredBy = [ "sleep.target" ];
    before = [ "sleep.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe lockBeforeSleep;
    };
  };
}
