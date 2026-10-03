{ pkgs, ... }:
let
  dumpDir = "/var/lib/courbet-devcoredump";

  saveDevcoredump = pkgs.writeShellScript "courbet-save-devcoredump" ''
    set -euo pipefail
    export PATH=${pkgs.coreutils}/bin
    dev=/sys/class/devcoredump/$1
    case $(readlink -f "$dev/failing_device") in
      */bluetooth/hci*)
        if [ "$(ls ${dumpDir} | wc -l)" -lt 50 ]; then
          cp "$dev/data" "${dumpDir}/$(date +%Y%m%d-%H%M%S)-$1.bin"
        fi
        echo 1 >"$dev/data"
        ;;
    esac
  '';
in
{
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="devcoredump", TAG+="systemd", ENV{SYSTEMD_WANTS}+="courbet-devcoredump@%k.service"
  '';

  systemd.services."courbet-devcoredump@" = {
    description = "Save the Bluetooth controller dump %i";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${saveDevcoredump} %i";
      StateDirectory = "courbet-devcoredump";
      StateDirectoryMode = "0700";
    };
  };

  systemd.services.courbet-btmon = {
    description = "Bluetooth HCI trace from boot";
    wantedBy = [ "bluetooth.service" ];
    before = [ "bluetooth.service" ];
    serviceConfig = {
      ExecStart = "${pkgs.bluez}/bin/btmon -w /var/log/btmon/%b.snoop";
      LogsDirectory = "btmon";
      LogsDirectoryMode = "0750";
    };
  };

  systemd.tmpfiles.rules = [
    "e /var/log/btmon - - - 7d"
    "e ${dumpDir} - - - 30d"
  ];
}
