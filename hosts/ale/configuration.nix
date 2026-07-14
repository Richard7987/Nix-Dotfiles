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

  # Binary cache oficial de Noctalia -- sin esto, cada rebuild compila
  # Noctalia desde fuente en vez de bajar el binario prearmado
  # (docs.noctalia.dev/v5/getting-started/nixos).
  #
  # Binary cache oficial de Psysonic (nixos-install.md del repo real, no
  # nixpkgs) -- sin esto, cada rebuild compila el frontend (npm) y el
  # binario Tauri (Rust) desde cero en vez de bajarlos ya armados. La build
  # que disparó este agregado (primer switch tras el cambio Feishin →
  # Psysonic) ya venía compilando en local antes de que esto se agregara --
  # no la acelera retroactivamente, pero sí los rebuilds futuros.
  nix.settings.extra-substituters = [
    "https://noctalia.cachix.org"
    "https://psysonic.cachix.org"
  ];
  nix.settings.extra-trusted-public-keys = [
    "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
    "psysonic.cachix.org-1:M9cQyQ7tgvUWOQ5Pyt8ozlMoPLtOZir6MfRuTH9/VYA="
  ];

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
  system.stateVersion = "26.05";
}
