{
  config,
  lib,
  pkgs,
  ...
}:
let
  panel = pkgs.writeText "xiaomi-courbet.json" (
    builtins.toJSON {
      name = "Xiaomi Mi 11 Lite 4G";
      x-res = 1080;
      y-res = 2400;
      corner-radii = [
        102
        102
        102
        102
      ];
      cutouts = [
        {
          name = "front-camera";
          path = "M 66,68 a 33.5,33.5 0 1,0 67,0 a 33.5,33.5 0 1,0 -67,0 Z";
        }
      ];
    }
  );

  entry = name: ''<file preprocess="json-stripblanks">devices/display-panels/${name}.json</file>'';

  gmobile = pkgs.gmobile.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      cp ${panel} 'data/devices/display-panels/xiaomi,courbet.json'
      substituteInPlace data/gmobile.gresources.xml \
        --replace-fail '${entry "xiaomi,curtana"}' '${entry "xiaomi,courbet"}${entry "xiaomi,curtana"}'
    '';
  });
in
{
  config = lib.mkIf config.services.xserver.desktopManager.phosh.enable {
    services.xserver.desktopManager.phosh.package = lib.mkDefault (
      (pkgs.phosh.override { inherit gmobile; }).overrideAttrs { doCheck = false; }
    );
  };
}
