{ pkgs, ... }:
let
  ucm2 = pkgs.runCommand "courbet-ucm2" { } ''
    cp -rs --no-preserve=mode ${pkgs.alsa-ucm-conf}/share/alsa/ucm2 $out
    install -Dm644 ${./ucm/HiFi.conf} $out/Xiaomi/courbet/HiFi.conf
    install -Dm644 ${./ucm/courbet.conf} "$out/conf.d/sm8250/Xiaomi Mi 11 Lite 4G.conf"
  '';
in
{
  environment.variables.ALSA_CONFIG_UCM2 = "${ucm2}";

  systemd.user.services = {
    pipewire.environment.ALSA_CONFIG_UCM2 = "${ucm2}";
    wireplumber.environment.ALSA_CONFIG_UCM2 = "${ucm2}";
  };

  services.pipewire.wireplumber.extraConfig."51-courbet-speakers" = {
    "monitor.alsa.rules" = [
      {
        matches = [ { "node.name" = "~alsa_output.platform-sound.*"; } ];
        actions.update-props."audio.format" = "S16LE";
      }
    ];
  };
}
