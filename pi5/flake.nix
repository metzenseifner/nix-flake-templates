# sd-image-aarch64.nix is designed around the U-Boot + extlinux flow. You're
# fighting the module the whole way. The cleaner approach is to not use that
# module at all and instead use the lower-level sd-image.nix directly, which
# gives you full control without the extlinux baggage.
# The base sd-image.nix module only cares about creating the partition layout
# (FAT firmware + ext4 root) and populating them via the two populate*Commands
# hooks. Everything else is up to you. It's the right abstraction level for Pi
# 5 where the boot chain is just: firmware → kernel.
{
  description = "Minimal bootable NixOS SD image for Raspberry Pi 5";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      system = "aarch64-linux";
    in
    {
      nixosConfigurations.pi5 = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          # Use the BASE sd-image module — not the aarch64 one
          "${nixpkgs}/nixos/modules/installer/sd-card/sd-image.nix"

          (
            {
              config,
              lib,
              pkgs,
              ...
            }:
            let
              kernel = config.boot.kernelPackages.kernel;
            in
            {
              # ── Boot ──
              # No bootloader — Pi 5 firmware loads kernel directly from FAT partition
              boot.loader.grub.enable = false;
              boot.loader.generic-extlinux-compatible.enable = false;

              boot.kernelPackages = pkgs.linuxPackages_latest;

              boot.kernelParams = [
                "console=ttyAMA10,115200"
                "console=tty1"
                "cma=256M"
                "root=/dev/disk/by-label/NIXOS_SD"
                "rootfstype=ext4"
                "rootwait"
              ];

              boot.initrd.availableKernelModules = [
                "xhci_pci"
                "usbhid"
                "usb_storage"
                "sd_mod"
                "sdhci_pci"
                "vc4"
                "v3d"
                "pcie_brcmstb"
                "nvme"
                "reset_raspberrypi"
              ];

              hardware.enableRedistributableFirmware = true;

              hardware.deviceTree = {
                enable = true;
                filter = "bcm2712*.dtb";
              };

              # ── SD image ──
              sdImage = {
                compressImage = true;
                firmwareSize = 256;
                expandOnBoot = true;
                # This is the FAT partition label the base module creates
                firmwarePartitionOffset = 8; # MiB offset for partition alignment on aarch64 systems

                # NixOS boot by having the kernel/initrd eventually switch_root to /mnt-root/ and exec /mnt-root/init.
                # This is a symlink /init -> /nix/store/xxxxx-nixos-system-pi5/init
                # sd-image.nix conventionally moves anything stored under ./files/ during populateRootCommands to the root partition
                # ./files/init becomes /init on the root partition, pointing into the Nix store. This is what stage 1 is looking for when it tries to exec /mnt-root/init.
                # ./files/nix/var/nix/profiles/system tells NixOS which system profile is active so that nixos-rebuild works in the future
                populateRootCommands = ''
                  mkdir -p ./files/nix/var/nix/profiles
                  ln -sf ${config.system.build.toplevel}/init ./files/init
                  ln -sf ${config.system.build.toplevel} ./files/nix/var/nix/profiles/system
                '';

                populateFirmwareCommands =
                  let
                    configTxt = pkgs.writeText "config.txt" ''
                      [all]
                      arm_64bit=1
                      os_check=0
                      kernel=Image
                      initramfs initrd followkernel
                      disable_overscan=1

                      [pi5]
                      dtparam=audio=on
                      dtparam=uart0=on
                    '';
                    cmdlineTxt = pkgs.writeText "cmdline.txt" (builtins.concatStringsSep " " config.boot.kernelParams);
                  in
                  ''
                    cp ${kernel}/Image firmware/Image
                    cp ${config.system.build.initialRamdisk}/initrd firmware/initrd

                    # DTBs — Pi firmware expects them at top level or in broadcom/
                    cp ${kernel}/dtbs/broadcom/bcm2712*.dtb firmware/ 2>/dev/null || true

                    # Overlays
                    if [ -d ${kernel}/dtbs/overlays ]; then
                      mkdir -p firmware/overlays
                      cp ${kernel}/dtbs/overlays/*.dtbo firmware/overlays/ 2>/dev/null || true
                    fi

                    cp ${configTxt} firmware/config.txt
                    cp ${cmdlineTxt} firmware/cmdline.txt
                  '';

              };

              # ── Networking ──
              networking = {
                hostName = "pi5";
                useDHCP = true;
                firewall.allowedTCPPorts = [ 22 ];
              };

              # ── SSH ──
              services.openssh = {
                enable = true;
                settings = {
                  PermitRootLogin = "prohibit-password";
                  PasswordAuthentication = false;
                };
              };

              # ── User ──
              users.users.admin = {
                isNormalUser = true;
                extraGroups = [
                  "wheel"
                  "video"
                  "gpio"
                  "i2c"
                  "spi"
                  "dialout"
                ];
                openssh.authorizedKeys.keys = [
                  "ssh-ed25519 AAAA... you@host"
                ];
              };

              security.sudo.wheelNeedsPassword = false;

              # ── Packages ──
              environment.systemPackages = with pkgs; [
                vim
                htop
                git
                usbutils
                pciutils
                i2c-tools
                raspberrypi-eeprom
                libraspberrypi
              ];

              # ── Strip bloat ──
              documentation.enable = false;
              documentation.man.enable = false;
              documentation.nixos.enable = false;
              fonts.fontconfig.enable = false;
              xdg.icons.enable = false;
              services.xserver.enable = false;

              # ── GPU ──
              hardware.graphics.enable = true;

              # ── Nix settings ──
              nix = {
                settings = {
                  experimental-features = [
                    "nix-command"
                    "flakes"
                  ];
                  auto-optimise-store = true;
                  max-jobs = 2;
                  cores = 4;
                };
                gc = {
                  automatic = true;
                  dates = "weekly";
                  options = "--delete-older-than 7d";
                };
              };

              system.stateVersion = "25.05";
            }
          )
        ];
      };

      packages.${system} = rec {
        sdImage = self.nixosConfigurations.pi5.config.system.build.sdImage;
        default = sdImage;
      };
    };
}
