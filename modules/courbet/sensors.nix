{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkIf mkOption types;
  cfg = config.hardware.courbet.sensors;

  suryaPmos = "ce9365f7d9d70eb511d8bd6b25cc6569060bce8e";

  hexagonrpc = pkgs.hexagonrpc.overrideAttrs (old: {
    version = "0.4.0-unstable-2026-03-20";
    src = pkgs.fetchFromGitHub {
      owner = "z3ntu";
      repo = "hexagonrpc";
      rev = "9f987970f9bc3e72081b7966a1f4e766ce6af6f7";
      hash = "sha256-7WJ1PdD/qVatXKwogro3ZoD4cJlwyL1HtJ6a62RuTBQ=";
    };
    patches =
      (old.patches or [ ])
      ++
        map
          (
            p:
            pkgs.fetchpatch {
              url = "https://raw.githubusercontent.com/woodyst/surya-pmos/${suryaPmos}/packages/hexagonrpcd/${p.name}";
              inherit (p) hash;
            }
          )
          [
            {
              name = "0001-apps_std-fix-strerror-using-wrong-error-source.patch";
              hash = "sha256-WArpEj5rWUSz5vwvvtaFTkqlRrBZBIkpNxHM2KPq8r0=";
            }
            {
              name = "0002-hexagonfs-add-read-write-support.patch";
              hash = "sha256-xMfhHsNPm3rS2uSqb/g7qILcYlP6o0YUwgkCe3Zmb2A=";
            }
            {
              name = "0003-add-writable-sensor-registry-directory-override.patch";
              hash = "sha256-kaTUU+bSIvj88cUgh7HszPhJLy19uqHQxoNoBEaOGgk=";
            }
            {
              name = "0004-listener-increase-inbuf-capacity.patch";
              hash = "sha256-xzYFAc+N9YLDXwofl80HWtPRCDAXfSqym1VsN7Mv6jg=";
            }
            {
              name = "0005-apps_std-implement-frename.patch";
              hash = "sha256-5g9+yZQBm3mRiPRv0uQ0X4OoO0KVXZ0teorSBaLeidI=";
            }
            {
              name = "0006-listener-dont-kill-connection-on-unsupported-call.patch";
              hash = "sha256-XjH/eHMeFBn43a+NhZw4iy2I5FoKLwh9i9EOBJ9cPO4=";
            }
            {
              name = "0008-apps_std-implement-ftell-and-flen.patch";
              hash = "sha256-38PKZQwTzC9jT3EzT0eC7qBFbwUYSZwbZLIizfTtONI=";
            }
          ]
      ++ [ ../../patches/hexagonrpc-map-display-sysfs.patch ];
  });

  libssc = pkgs.libssc.overrideAttrs (old: {
    patches =
      (old.patches or [ ])
      ++
        map
          (
            p:
            pkgs.fetchpatch {
              url = "https://codeberg.org/DylanVanAssche/libssc/commit/${p.rev}.patch";
              inherit (p) hash;
            }
          )
          [
            {
              rev = "167fff52e3fc91630f8ad6ac892942eb6ae1a9c8";
              hash = "sha256-YkGufi1OCldHxtTQB7Mp1gDzs50xuLCxLTN+7xu09qk=";
            }
            {
              rev = "54dd13e36d65c21263cf5b0f4a70c230a77b26bc";
              hash = "sha256-wQoHZliSkiSCBcLlNmsKyg3fi/M/9OIonfHca/tEwxs=";
            }
            {
              rev = "f54187cd601260415b47efba7fc2985d28c3e810";
              hash = "sha256-NDEVS0xhiHddvugpI8vuEIXtYdSYXIBRSPxLObMtXrg=";
            }
          ]
      ++ [ ../../patches/libssc-log-error-before-returning-it.patch ];
  });

  firmware = pkgs.fetchFromGitHub {
    owner = "sm7150-mainline";
    repo = "firmware-xiaomi-courbet";
    rev = "9f008a4f92e871db59475ec91a65bd82d410a899";
    hash = "sha256-mz2r2HdRBkEfddyNUZf0wE7U5mla8ANNwGvETnNH+rg=";
  };

  root = "/var/lib/hexagonrpcd/courbet";
  persist = "/run/firmware/persist";

  seed = pkgs.writeShellScript "courbet-sensors-seed" ''
    set -euo pipefail
    export PATH=${lib.makeBinPath [ pkgs.coreutils ]}
    install -d -m 0755 ${root} ${root}/dsp ${root}/sensors ${root}/socinfo ${root}/acdb
    ln -sfn ${firmware}/usr/lib/qcom/adsp ${root}/dsp/adsp
    ln -sfn ${firmware}/etc/qcom/sensors.d ${root}/sensors/config
    ln -sfn ${firmware}/etc/qcom/sns_reg.conf ${root}/sensors/sns_reg.conf
    cat /sys/devices/soc0/soc_id >${root}/socinfo/soc_id
    cat /sys/devices/soc0/revision >${root}/socinfo/revision
    echo QRD >${root}/socinfo/hw_platform
    echo QRD >${root}/socinfo/platform_subtype
    echo 0 >${root}/socinfo/platform_subtype_id
    echo 0 >${root}/socinfo/platform_version
    ln -sfn /sys/class/backlight/ae94000.dsi.0 ${root}/backlight
    install -d -m 0755 ${root}/display
    echo 90 >${root}/display/dynamic_fps
    install -d -m 0755 -o fastrpc -g fastrpc ${root}/registry ${root}/registry/registry
    if [ -d ${persist}/sensors/registry/registry ]; then
      src=${persist}/sensors/registry
    else
      src=${firmware}/var/lib/qcom/sensors
    fi
    cp -rn --no-preserve=mode,ownership "$src"/registry/. ${root}/registry/registry/
    if [ ! -e ${root}/registry/sns_reg_version ]; then
      if [ -e "$src"/sns_reg_version ]; then
        cp --no-preserve=mode,ownership "$src"/sns_reg_version ${root}/registry/sns_reg_version
      else
        head -n 1 ${firmware}/etc/qcom/sns_reg.conf >${root}/registry/sns_reg_version
      fi
    fi
    chown -R fastrpc:fastrpc ${root}/registry
    chmod -R u+rwX ${root}/registry
  '';

  started = "/run/hexagonrpcd-sensorspd/started";

  waitForSsc = pkgs.writeShellScript "courbet-wait-for-ssc" ''
    export PATH=${lib.makeBinPath [ pkgs.coreutils ]}
    registry=${root}/registry/registry
    settle=$((SECONDS + 15))
    until [ "$registry" -nt ${started} ] || [ "$SECONDS" -ge "$settle" ]; do
      sleep 0.2
    done
    last=
    while [ "$SECONDS" -lt "$settle" ]; do
      now=$(stat -c %y "$registry")
      [ "$now" = "$last" ] && break
      last=$now
      sleep 2
    done
    end=$((SECONDS + 60))
    until timeout 40 ${libssc}/bin/ssccli --sensor accelerometer --timeout 1 >/dev/null; do
      [ "$SECONDS" -lt "$end" ] || exit 1
      sleep 1
    done
  '';

  daemon = sensorspd: {
    description = "Qualcomm ADSP ${if sensorspd then "sensor" else "root"} domain file server";
    bindsTo = [ "dev-fastrpc\\x2dadsp.device" ];
    requires = [ "courbet-sensors-seed.service" ];
    after = [
      "dev-fastrpc\\x2dadsp.device"
      "courbet-sensors-seed.service"
    ];
    serviceConfig = {
      ExecStart = "${hexagonrpc}/bin/hexagonrpcd -f /dev/fastrpc-adsp -d adsp -R ${root}${lib.optionalString sensorspd " -s -P ${root}/registry"}";
      User = "fastrpc";
      Group = "fastrpc";
      Restart = "always";
      RestartSec = 3;
    }
    // lib.optionalAttrs sensorspd {
      RuntimeDirectory = "hexagonrpcd-sensorspd";
      ExecStartPre = "${pkgs.coreutils}/bin/touch ${started}";
      ExecStartPost = "-${waitForSsc}";
      TimeoutStartSec = 150;
    };
  };
in
{
  options.hardware.courbet.sensors.enable = mkOption {
    type = types.bool;
    default = true;
    description = "Whether to serve the ADSP sensor domain with hexagonrpcd so the SSC sensors work.";
  };

  config = mkIf cfg.enable {
    users.users.fastrpc = {
      isSystemUser = true;
      group = "fastrpc";
    };
    users.groups.fastrpc = { };

    fileSystems.${persist} = {
      device = "/dev/disk/by-partlabel/persist";
      fsType = "ext4";
      noCheck = true;
      options = [
        "ro"
        "noload"
        "nofail"
        "x-systemd.device-timeout=10s"
      ];
    };

    services.udev.extraRules = ''
      SUBSYSTEM=="misc", KERNEL=="fastrpc-*", GROUP="fastrpc", MODE="0660"
      ACTION=="add", SUBSYSTEM=="misc", KERNEL=="fastrpc-adsp", TAG+="systemd", ENV{SYSTEMD_WANTS}+="hexagonrpcd-adsp-rootpd.service hexagonrpcd-adsp-sensorspd.service"
      SUBSYSTEM=="misc", KERNEL=="fastrpc-adsp", ENV{IIO_SENSOR_PROXY_TYPE}+="ssc-accel", ENV{ACCEL_MOUNT_MATRIX}="-1, 0, 0; 0, -1, 0; 0, 0, 1"
    '';

    systemd.services = {
      courbet-sensors-seed = {
        description = "Writable ADSP sensor registry for hexagonrpcd";
        wants = [ "run-firmware-persist.mount" ];
        after = [ "run-firmware-persist.mount" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = seed;
        };
      };
      hexagonrpcd-adsp-rootpd = daemon false;
      hexagonrpcd-adsp-sensorspd = daemon true;
      iio-sensor-proxy = {
        bindsTo = [ "hexagonrpcd-adsp-sensorspd.service" ];
        after = [ "hexagonrpcd-adsp-sensorspd.service" ];
      };
    };

    hardware.sensor.iio = {
      enable = true;
      package = (pkgs.iio-sensor-proxy.override { inherit libssc; }).overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [
          (pkgs.fetchpatch {
            url = "https://gitlab.freedesktop.org/hadess/iio-sensor-proxy/-/commit/e21ca257d742c69b757aca5a4d2c3b7787306034.patch";
            hash = "sha256-TO6dSoK3KWPthWBTn7YzGyLtfGFn2sgkdVHQUlLdAq0=";
          })
          ../../patches/iio-sensor-proxy-claim-before-open.patch
        ];
      });
    };
  };
}
