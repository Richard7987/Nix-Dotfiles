# ESTE ARCHIVO ES UN PLACEHOLDER.
#
# Reemplázalo COMPLETO por el que genera el propio instalador de NixOS:
#   nixos-generate-config --root /mnt     (durante la instalación)
#   doas nixos-generate-config            (en un sistema ya instalado, regenera
#                                           /etc/nixos/hardware-configuration.nix)
#
# Copia ese archivo real aquí tal cual — contiene los UUIDs de tus particiones,
# módulos de kernel detectados y demás, que son específicos de esta máquina y
# no se pueden adivinar de antemano.
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  # boot.initrd.availableKernelModules = [ ... ];
  # boot.initrd.kernelModules = [ ... ];
  # boot.kernelModules = [ "kvm-intel" ];
  # boot.extraModulePackages = [ ... ];

  # fileSystems."/" = {
  #   device = "/dev/disk/by-uuid/CAMBIAR-ESTO";
  #   fsType = "ext4";
  # };

  # swapDevices = [ ... ];

  # networking.useDHCP = lib.mkDefault true;

  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  hardware.enableRedistributableFirmware = lib.mkDefault true;
}
