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

  toolchain = [
    llvm.clang-unwrapped
    llvm.lld
    llvm.llvm
  ];

  ccacheConf = pkgs.writeText "ccache.conf" ''
    compression = true
    max_size = 300G
    sloppiness = include_file_mtime,include_file_ctime,random_seed
    umask = 000
  '';

  configfile = pkgs.stdenv.mkDerivation {
    name = "linux-courbet.config";
    inherit src;

    nativeBuildInputs = toolchain ++ [
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
  inherit version src configfile;
  modDirVersion = "${version}-sm7150";
  target = "Image.gz";
  buildDTBs = false;
  allowImportFromDerivation = true;
  stdenv = cross.stdenvNoCC;
}).overrideAttrs
  (prev: {
    nativeBuildInputs = prev.nativeBuildInputs ++ toolchain ++ [ pkgs.ccache ];
    makeFlags = [
      "O=$(buildRoot)"
      "--eval=undefine modules"
    ]
    ++ kbuildFlags
    ++ [ "CC=ccache clang" ];
    preConfigure = ''
      export CCACHE_DIR=/nix/ccache
      export CCACHE_CONFIGPATH=${ccacheConf}
      export CCACHE_COMPILERCHECK=string:${llvm.clang-unwrapped}
      if [ ! -w "$CCACHE_DIR" ]; then
        export CCACHE_DISABLE=1
      fi
    ''
    + (prev.preConfigure or "");
    buildFlags = prev.buildFlags ++ [ "qcom/sm7150-xiaomi-courbet.dtb" ];
    postInstall = ''
      install -Dm644 $buildRoot/arch/arm64/boot/dts/qcom/sm7150-xiaomi-courbet.dtb \
        $out/dtbs/qcom/sm7150-xiaomi-courbet.dtb
    ''
    + prev.postInstall;
  })
