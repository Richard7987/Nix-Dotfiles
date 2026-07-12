{ config, lib, pkgs, inputs, ... }:

{
  # --- Hyprland ---
  # El módulo de NixOS ya habilita polkit, xdg-desktop-portal-hyprland, dconf,
  # xwayland y añade la entrada de sesión al display manager — no hace falta
  # configurar eso a mano.
  programs.hyprland.enable = true;

  # --- Requisitos de Noctalia (docs.noctalia.dev/v5/getting-started/nixos) ---
  networking.networkmanager.enable = true;
  hardware.bluetooth.enable = true;
  services.power-profiles-daemon.enable = true;
  services.upower.enable = true;

  # --- Audio (pipewire) — necesario para que los atajos wpctl del hyprland.lua funcionen ---
  security.rtkit.enable = true;
  hardware.pulseaudio.enable = false;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    wireplumber.enable = true;
  };

  # --- Noctalia shell (módulo NixOS, instala el paquete a nivel de sistema) ---
  programs.noctalia = {
    enable = true;
    recommendedServices.enable = true;
  };

  # --- Noctalia Greeter ---
  # Greeter oficial hecho para Noctalia: usa greetd + un compositor wlroots
  # propio y comparte el mismo lenguaje visual (tema/colores/wallpaper) que
  # el shell. Es el que mejor encaja con Noctalia (en vez de SDDM/tuigreet).
  programs.noctalia-greeter = {
    enable = true;
    greeter-args = "--session hyprland"; # verifica el nombre exacto con `noctalia-greeter sessions`
  };

  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    noto-fonts
    noto-fonts-emoji
  ];

  environment.systemPackages = with pkgs; [
    kdePackages.kleopatra
    inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.default
    kitty          # terminal usada en hyprland.lua (mainMod+Return)
    brightnessctl  # atajos de brillo en hyprland.lua
  ];
}
