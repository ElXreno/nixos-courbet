{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;
  cfg = config.hardware.courbet.chargeLimit;

  battery = "/sys/class/power_supply/qcom_qg";
  devices = [
    "sys-class-power_supply-qcom_qg.device"
    "sys-class-power_supply-pm8150b\\x2dcharger.device"
  ];
in
{
  options.hardware.courbet.chargeLimit = {
    enable = mkEnableOption "holding the battery between the start and stop thresholds on external power";

    start = mkOption {
      type = types.ints.between 0 100;
      default = 75;
      description = "Capacity in percent below which a charged battery starts charging again.";
    };

    stop = mkOption {
      type = types.ints.between 0 100;
      default = 80;
      description = "Capacity in percent at which the charger terminates charging.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.start < cfg.stop;
        message = "hardware.courbet.chargeLimit.start must be below hardware.courbet.chargeLimit.stop";
      }
    ];

    services.udev.extraRules = ''
      SUBSYSTEM=="power_supply", KERNEL=="qcom_qg|pm8150b-charger", TAG+="systemd", ENV{SYSTEMD_ALIAS}+="/sys/class/power_supply/%k"
    '';

    systemd.services.courbet-charge-thresholds = {
      description = "Battery charge thresholds";
      wantedBy = [ "multi-user.target" ];
      requires = devices;
      after = devices;
      unitConfig = {
        StartLimitIntervalSec = 60;
        StartLimitBurst = 10;
      };
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = "2s";
        ExecStart = pkgs.writeShellScript "courbet-charge-thresholds" ''
          set -eu
          echo ${toString cfg.start} >${battery}/charge_control_start_threshold
          echo ${toString cfg.stop} >${battery}/charge_control_end_threshold
        '';
      };
    };
  };
}
