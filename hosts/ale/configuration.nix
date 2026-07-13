{ config, pkgs, lib, inputs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/graphics.nix
    ../../modules/yubikey.nix
    ../../modules/tailscale.nix
    ../../modules/desktop.nix
  ];

  # --- Boot ---
  # Asume arranque UEFI (normal en cualquier laptop de los últimos ~10 años).
  # Si tu equipo arranca en modo BIOS/legacy (raro, pero posible), esto va a
  # fallar al instalar el bootloader -- en ese caso cambia por:
  #   boot.loader.grub.enable = true;
  #   boot.loader.grub.device = "/dev/sdX";  # disco completo, no partición
  # y quita las dos líneas de systemd-boot/efi de abajo.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # --- Red ---
  networking.hostName = "ale";
  # networking.networkmanager.enable ya se activa en modules/desktop.nix (requisito de Noctalia)

  # --- Zona horaria / locale ---
  time.timeZone = lib.mkDefault "America/Mexico_City"; # AJUSTAR si no es tu zona
  i18n.defaultLocale = "es_MX.UTF-8";

  # --- Usuario ---
  users.users.ale = {
    isNormalUser = true;
    description = "ale";
    extraGroups = [ "wheel" "networkmanager" "video" "input" "dialout" ];
    shell = pkgs.zsh;
  };
  programs.zsh.enable = true;

  # --- Nix ---
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nixpkgs.config.allowUnfree = true; # necesario para el driver Nvidia y Steam

  environment.systemPackages = with pkgs; [
    git
    vim
    curl
    wget
    claude-code
  ];

  # NUNCA cambies este valor después de la instalación inicial (ver `man configuration.nix`,
  # sección system.stateVersion). Reemplázalo por el que te haya dado el instalador de NixOS
  # antes de correr el primer `nixos-rebuild switch`.
  system.stateVersion = "25.05"; # <-- AJUSTAR
}
