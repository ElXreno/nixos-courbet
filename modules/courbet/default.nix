{ kernel }:
{ lib, pkgs, ... }:
let
  bootimg = import ../../bootimg.nix;

  partition = ''
    partition() {
      for u in /sys/class/block/*/uevent; do
        if grep -qx "PARTNAME=$1" "$u"; then
          echo "/dev/$(basename "$(dirname "$u")")"
          return
        fi
      done
      echo "partition $1 not found" >&2
      return 1
    }
  '';

  remoteprocFirmware =
    pkgs.runCommand "courbet-remoteproc-firmware" { passthru.compressFirmware = false; }
      ''
        img=/run/firmware/modem/image
        fw=$out/lib/firmware/qcom/sm7150/xiaomi/courbet
        mkdir -p $fw
        for f in cdsp modem; do
          ln -s $img/$f.mdt $fw/$f.mbn
          for i in $(seq -w 0 49); do
            ln -s $img/$f.b$i $fw/$f.b$i
          done
        done
        for f in modem_pr wlanmdsp.mbn; do
          ln -s $img/$f $fw/$f
        done
      '';

  qcaSwissArmyKnife = pkgs.fetchFromGitHub {
    owner = "qca";
    repo = "qca-swiss-army-knife";
    rev = "6df4dae3e2f5e4c2903f3cafd40996fc1b3639ce";
    hash = "sha256-FFoV58YVK7KGBw/JPFWcvGkJOONrfKCvACprYCzIKeg=";
  };

  wifiFirmware =
    pkgs.runCommand "courbet-wifi-firmware"
      {
        nativeBuildInputs = [ pkgs.python3 ];
        passthru.compressFirmware = false;
      }
      ''
        fw=$out/lib/firmware/ath10k/WCN3990/hw1.0/sm7150
        mkdir -p $fw
        python3 ${qcaSwissArmyKnife}/tools/scripts/ath10k/ath10k-fwencoder --create \
          --set-fw-api=5 --set-wmi-op-version=tlv --set-htt-op-version=tlv \
          --features=wowlan,mfp-support,mgmt-tx-by-ref,non-bmi,single-chan-info-per-channel \
          --timestamp=0 --output=$fw/firmware-5.bin
        ln -s /run/firmware/modem/image/bd_k9a.bin $fw/board.bin
      '';

  wifiMac = pkgs.writeShellScript "courbet-wifi-mac" ''
    set -euo pipefail
    mac=$(${pkgs.libqmi}/bin/qmicli -d qrtr://0 --dms-get-mac-address=wlan |
      ${pkgs.gnugrep}/bin/grep -oiE '([0-9a-f]{2}:){5}[0-9a-f]{2}')
    ${pkgs.iproute2}/bin/ip link set dev "$1" address "$mac"
  '';

  bluetoothAddress = pkgs.writeShellScript "courbet-bluetooth-address" ''
    set -euo pipefail
    export PATH=${
      lib.makeBinPath [
        pkgs.bluez
        pkgs.coreutils
        pkgs.gnugrep
        pkgs.libqmi
      ]
    }
    for _ in $(seq 60); do
      cfg=$(btmgmt --index "$1" config 2>/dev/null || true)
      case $cfg in
        *"missing options: public-address"*) break ;;
        *"missing options:"*) exit 0 ;;
      esac
      sleep 1
    done
    for _ in $(seq 60); do
      raw=$(qmicli -d qrtr://0 --dms-get-mac-address=bt 2>/dev/null |
        grep -oiE '([0-9a-f]{2}:){5}[0-9a-f]{2}') && break
      sleep 1
    done
    btmgmt --index "$1" public-addr "$(printf '%s\n' "$raw" | tr : '\n' | tac | paste -sd:)"
  '';

  gpuFirmware = pkgs.runCommand "courbet-gpu-firmware" { } ''
    for f in a630_sqe.fw a630_gmu.bin; do
      install -Dm644 ${pkgs.linux-firmware}/lib/firmware/qcom/$f $out/lib/firmware/qcom/$f
    done
  '';

  bluetoothFirmware = pkgs.runCommand "courbet-bluetooth-firmware" { } ''
    for f in crbtfw21.tlv crnv21.bin; do
      install -Dm644 ${pkgs.linux-firmware}/lib/firmware/qca/$f $out/lib/firmware/qca/$f
    done
  '';

  firmwarePartition = name: {
    device = "/dev/disk/by-partlabel/${name}";
    fsType = "vfat";
    options = [
      "ro"
      "noatime"
      "nofail"
      "x-systemd.device-timeout=10s"
    ];
  };
in
{
  imports = [
    ./gpu.nix
    ./ipa.nix
    ./panel.nix
  ];

  nixpkgs.hostPlatform = "aarch64-linux";

  boot = {
    kernelPackages = pkgs.linuxPackagesFor kernel;
    kernelParams = [
      "console=tty0"
      "clk_ignore_unused"
      "pd_ignore_unused"
    ];
    kernelModules = [ "qcom_pd_mapper" ];

    initrd = {
      systemd = {
        enable = true;
        tpm2.enable = false;
      };
      includeDefaultModules = false;
    };

    loader = {
      grub.enable = false;
      external = {
        enable = true;
        installHook = pkgs.writeShellScript "install-courbet-bootimg" ''
          set -euo pipefail
          export PATH=${
            lib.makeBinPath [
              pkgs.coreutils
              pkgs.diffutils
              pkgs.gnugrep
            ]
          }
          ${partition}
          img=$(mktemp)
          trap 'rm -f "$img"' EXIT
          ${bootimg.fromSystem "${pkgs.android-tools}/bin/mkbootimg" "$1" "$img"}
          dev=$(partition boot)
          if ! cmp -s -n "$(stat -c %s "$img")" "$img" "$dev"; then
            dd if="$img" of="$dev" bs=4M conv=fsync status=none
          fi
        '';
      };
    };
  };

  system.boot.loader.kernelFile = "Image.gz";

  hardware.deviceTree.enable = true;

  systemd.tpm2.enable = false;

  systemd.settings.Manager = {
    RebootWatchdogSec = "30s";
    RuntimeWatchdogSec = "30s";
  };

  fileSystems = {
    "/run/firmware/modem" = firmwarePartition "modem";
    "/run/firmware/bluetooth" = firmwarePartition "bluetooth";
  };

  hardware.firmware = [
    bluetoothFirmware
    gpuFirmware
    remoteprocFirmware
    wifiFirmware
  ];

  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="net", DRIVERS=="ath10k_snoc", RUN+="${wifiMac} $name"
    ACTION=="add", SUBSYSTEM=="bluetooth", ENV{DEVTYPE}=="host", DRIVERS=="hci_uart_qca", TAG+="systemd", ENV{SYSTEMD_WANTS}+="courbet-bluetooth-address@%k.service"
  '';

  systemd.services."courbet-bluetooth-address@" = {
    description = "Bluetooth public address of %i from the modem NV";
    after = [ "rmtfs.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${bluetoothAddress} %i";
    };
  };

  systemd.services.systemd-udevd.serviceConfig.RestrictAddressFamilies = [ "AF_QIPCRTR" ];

  systemd.services.tqftpserv = {
    description = "QRTR TFTP service for remote processors";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.tqftpserv}/bin/tqftpserv";
      Restart = "always";
      RestartSec = 1;
    };
  };

  systemd.services.rmtfs = {
    description = "Qualcomm remote filesystem service for the modem";
    wantedBy = [ "multi-user.target" ];
    requires = [ "run-firmware-modem.mount" ];
    wants = [
      "network-pre.target"
      "tqftpserv.service"
    ];
    after = [
      "run-firmware-modem.mount"
      "tqftpserv.service"
    ];
    before = [ "network-pre.target" ];
    startLimitIntervalSec = 0;
    serviceConfig = {
      ExecStart = "${pkgs.rmtfs}/bin/rmtfs -r -P -s";
      Restart = "always";
      RestartSec = 1;
    };
  };

  systemd.services.usb-gadget = {
    description = "USB gadget with NCM networking and ACM console";
    wantedBy = [ "sysinit.target" ];
    wants = [ "network-pre.target" ];
    before = [
      "network-pre.target"
      "serial-getty@ttyGS0.service"
    ];
    requires = [ "sys-kernel-config.mount" ];
    after = [ "sys-kernel-config.mount" ];
    unitConfig.DefaultDependencies = false;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      g=/sys/kernel/config/usb_gadget/g1
      if [ -e $g/UDC ] && [ -n "$(cat $g/UDC)" ]; then
        exit 0
      fi
      mkdir -p $g/strings/0x409 $g/functions/ncm.usb0 $g/functions/acm.usb0 $g/configs/c.1/strings/0x409
      echo 0x18d1 >$g/idVendor
      echo 0xd001 >$g/idProduct
      echo courbet >$g/strings/0x409/serialnumber
      echo courbet >$g/strings/0x409/product
      echo ncm+acm >$g/configs/c.1/strings/0x409/configuration
      echo 02:62:6f:62:65:01 >$g/functions/ncm.usb0/host_addr
      echo 02:62:6f:62:65:02 >$g/functions/ncm.usb0/dev_addr
      ln -sf $g/functions/ncm.usb0 $g/configs/c.1/
      ln -sf $g/functions/acm.usb0 $g/configs/c.1/
      for _ in $(seq 100); do
        [ -n "$(ls /sys/class/udc)" ] && break
        sleep 0.1
      done
      ls /sys/class/udc | head -n 1 >$g/UDC
    '';
  };

  systemd.targets.getty.wants = [ "serial-getty@ttyGS0.service" ];

  networking.useNetworkd = true;
  networking.networkmanager.unmanaged = [ "usb0" ];
  systemd.network.networks."40-usb0" = {
    matchConfig.Name = "usb0";
    networkConfig = {
      Address = "172.16.42.1/24";
      DHCPServer = true;
      ConfigureWithoutCarrier = true;
    };
    dhcpServerConfig = {
      PoolOffset = 2;
      PoolSize = 1;
    };
    linkConfig.RequiredForOnline = "no";
  };
}
