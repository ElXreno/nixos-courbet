{
  pkgs,
  src,
  llvm,
  kbuildFlags,
}:
let
  cross = pkgs.pkgsCross.aarch64-multiplatform;

  inherit (pkgs) lib;

  makefile = lib.splitString "\n" (builtins.readFile "${src}/Makefile");
  makeVar =
    name: lib.removePrefix "${name} = " (lib.findFirst (lib.hasPrefix "${name} = ") "" makefile);
  version = "${makeVar "VERSION"}.${makeVar "PATCHLEVEL"}.${makeVar "SUBLEVEL"}${makeVar "EXTRAVERSION"}";

  crossLlvm = cross.buildPackages."llvmPackages_${lib.versions.major llvm.release_version}";

  stdenv = cross.stdenvAdapters.overrideCC cross.stdenv (
    crossLlvm.clangNoCompilerRt.override { bintools = crossLlvm.bintoolsNoLibc; }
  );

  configfile = pkgs.stdenv.mkDerivation {
    name = "linux-courbet.config";
    inherit src;

    nativeBuildInputs = [
      llvm.clang-unwrapped
      llvm.lld
      llvm.llvm
      pkgs.bison
      pkgs.flex
      pkgs.openssl
      pkgs.perl
    ];

    dontConfigure = true;

    buildPhase = ''
      runHook preBuild
      patchShebangs scripts
      make O=build ${toString kbuildFlags} defconfig sm7150.config
      scripts/kconfig/merge_config.sh -m -O build build/.config ${./extra.config}
      make O=build ${toString kbuildFlags} olddefconfig
      runHook postBuild
    '';

    installPhase = ''
      cp build/.config $out
    '';
  };
in
(cross.linuxManualConfig {
  inherit
    version
    src
    configfile
    stdenv
    ;
  modDirVersion = "${version}-sm7150";
  target = "Image.gz";
  buildDTBs = false;
  allowImportFromDerivation = true;
}).overrideAttrs
  (prev: {
    buildFlags = prev.buildFlags ++ [ "qcom/sm7150-xiaomi-courbet.dtb" ];
    postInstall = ''
      install -Dm644 $buildRoot/arch/arm64/boot/dts/qcom/sm7150-xiaomi-courbet.dtb \
        $out/dtbs/qcom/sm7150-xiaomi-courbet.dtb
    ''
    + prev.postInstall;
  })
