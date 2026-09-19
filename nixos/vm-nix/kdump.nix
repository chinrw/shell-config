{
  config,
  lib,
  pkgs,
  ...
}:

let
  kernel = config.boot.kernelPackages.kernel;
  root = config.fileSystems."/";
  dumpPath = "/var/lib/kdump";

  saveDump = pkgs.writeShellApplication {
    name = "kdump-save";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.util-linux
      pkgs.kexec-tools
    ];
    text = ''
      umask 077
      test -r /proc/vmcore

      for _attempt in {1..60}; do
        if test -b ${lib.escapeShellArg root.device}; then
          break
        fi
        sleep 1
      done

      mkdir -p /run/kdump-root
      mount -t ${lib.escapeShellArg root.fsType} \
        -o ${lib.escapeShellArg (lib.concatStringsSep "," root.options)} \
        ${lib.escapeShellArg root.device} /run/kdump-root
      destination=/run/kdump-root${dumpPath}
      install -d -m 0700 "$destination"
      capture=$(mktemp -d "$destination/$(date -u +%Y%m%dT%H%M%SZ)-XXXXXX")

      finish() {
        status=$?
        trap - EXIT
        if test "$status" -ne 0; then
          printf 'Capture failed with exit status %s\n' "$status" > "$capture/FAILED"
        fi
        dmesg > "$capture/capture-kernel.log" || true
        sync -f "$capture" || true
        exit "$status"
      }
      trap finish EXIT

      cp /proc/cmdline "$capture/capture-cmdline"
      ${pkgs.kexec-tools}/bin/vmcore-dmesg /proc/vmcore > "$capture/dmesg.txt" || true
      available=$(df --output=avail -B1 "$capture" | tail -n 1)
      required=$(stat --format=%s /proc/vmcore)
      if (( available < required + 1024 * 1024 * 1024 )); then
        echo 'Insufficient space for a full vmcore plus 1 GiB of headroom.' >&2
        exit 1
      fi
      printf 'Saving vmcore to %s\n' "$capture"
      # Keep partial dumps distinguishable when a write fails or times out.
      cp --sparse=always /proc/vmcore "$capture/vmcore.partial"
      sync -f "$capture/vmcore.partial"
      mv "$capture/vmcore.partial" "$capture/vmcore"
      touch "$capture/COMPLETE"
      sync -f "$capture"
      printf 'Saved vmcore to %s\n' "$capture"
    '';
  };

in
{
  assertions = [
    {
      assertion = config.boot.initrd.systemd.enable;
      message = "vm-nix kdump requires the systemd initrd.";
    }
  ];

  boot.crashDump = {
    enable = true;
    reservedMemory = "1G";
    kernelParams = [
      "rd.systemd.unit=kdump.target"
      "nr_cpus=1"
      "panic=30"
    ];
  };
  # The stock module enables lockup panics; VM scheduling stalls can recover.
  boot.kernelParams = lib.mkAfter [
    "nmi_watchdog=0"
    "softlockup_panic=0"
  ];
  boot.kernel.sysctl = {
    "kernel.panic_on_oops" = 1;
    "kernel.panic" = 30;
    "kernel.hardlockup_panic" = 0;
  };
  system.extraDependencies = [ kernel.dev ];

  boot.initrd.systemd.storePaths = [
    saveDump
    "${pkgs.kexec-tools}/bin/vmcore-dmesg"
  ];
  boot.initrd.systemd.targets.kdump = {
    description = "Save the crashed kernel without starting the normal system";
    requires = [ "kdump-save.service" ];
    after = [ "kdump-save.service" ];
    unitConfig = {
      DefaultDependencies = false;
      JobTimeoutSec = "10min";
      JobTimeoutAction = "reboot-force";
    };
  };
  boot.initrd.systemd.services.kdump-save = {
    description = "Save vmcore to the local root filesystem";
    wants = [
      "systemd-udev-trigger.service"
      "systemd-modules-load.service"
    ];
    after = [
      "systemd-udev-trigger.service"
      "systemd-modules-load.service"
    ];
    unitConfig = {
      DefaultDependencies = false;
      SuccessAction = "reboot-force";
      FailureAction = "reboot-force";
    };
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${saveDump}/bin/kdump-save";
      TimeoutStartSec = "10min";
      TimeoutStopSec = "15s";
      StandardOutput = "tty";
      StandardError = "inherit";
      TTYPath = "/dev/console";
    };
  };
}
