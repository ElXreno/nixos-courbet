let
  args = toString [
    "--header_version 2"
    "--pagesize 4096"
    "--base 0x0"
    "--kernel_offset 0x8000"
    "--ramdisk_offset 0x01000000"
    "--tags_offset 0x100"
    "--dtb_offset 0x01f00000"
    "--os_version 16.0.0"
    "--os_patch_level 2026-09"
  ];

  dtb = "qcom/sm7150-xiaomi-courbet.dtb";
in
{
  inherit args dtb;

  fromSystem = mkbootimg: system: out: ''
    ${mkbootimg} ${args} \
      --kernel "${system}/kernel" \
      --dtb "${system}/dtbs/${dtb}" \
      --ramdisk "${system}/initrd" \
      --cmdline "init=${system}/init $(cat "${system}/kernel-params")" \
      -o "${out}"
  '';
}
