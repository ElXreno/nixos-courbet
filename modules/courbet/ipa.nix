{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkIf mkOption types;
  cfg = config.hardware.courbet;
in
{
  options.hardware.courbet.ipaFirmware = mkOption {
    type = types.nullOr types.path;
    default = null;
    description = "Signed IPA GSI firmware (`ipa_fws.mbn`) from the vendor partition, loaded by the AP for the modem data path.";
  };

  config = mkIf (cfg.ipaFirmware != null) {
    hardware.firmware = [
      (pkgs.runCommand "courbet-ipa-firmware" { } ''
        install -Dm644 ${cfg.ipaFirmware} $out/lib/firmware/qcom/sm7150/xiaomi/courbet/ipa_fws.mbn
      '')
    ];
  };
}
