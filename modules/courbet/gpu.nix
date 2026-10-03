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
  options.hardware.courbet.zapShader = mkOption {
    type = types.nullOr types.path;
    default = null;
    description = "Signed Adreno 615 zap shader (`a615_zap.mbn`) from the vendor partition, required for GPU acceleration.";
  };

  config = mkIf (cfg.zapShader != null) {
    boot.initrd.extraFirmwarePaths = [
      "qcom/a630_gmu.bin.zst"
      "qcom/a630_sqe.fw.zst"
      "qcom/sm7150/xiaomi/courbet/a615_zap.mbn.zst"
    ];

    hardware.firmware = [
      (pkgs.runCommand "courbet-gpu-zap" { } ''
        install -Dm644 ${cfg.zapShader} $out/lib/firmware/qcom/sm7150/xiaomi/courbet/a615_zap.mbn
      '')
    ];
  };
}
