{ config, lib, pkgs, inputs, ... }:

{
  # --- Hyprland ---
  # El módulo de NixOS ya habilita polkit, xdg-desktop-portal-hyprland, dconf,
  # xwayland y añade la entrada de sesión al display manager — no hace falta
  # configurar eso a mano.
  programs.hyprland.enable = true;

  # pkexec necesita el wrapper setuid de NixOS para funcionar (el binario
  # crudo del store no tiene setuid). Sin esto:
  #   - el propio módulo de gamemode (modules/graphics.nix) apunta su
  #     servicio systemd a "${security.wrapperDir}/pkexec", que no existiría
  #     -> las operaciones privilegiadas de gamemode (cpugovctl/gpuclockctl)
  #     fallarían.
  #   - la función "Sync Now" de noctalia-greeter (sincroniza tema/wallpaper
  #     del greeter con el shell) también depende de pkexec en PATH y
  #     funcional -- es un problema documentado ("Sync fails with no
  #     privilege escalator") cuando pkexec está deshabilitado en NixOS.
  security.polkit.enablePkexecWrapper = true;

  # --- Requisitos de Noctalia (docs.noctalia.dev/v5/getting-started/nixos) ---
  networking.networkmanager.enable = true;
  hardware.bluetooth.enable = true;
  services.power-profiles-daemon.enable = true;
  services.upower.enable = true;

  # --- Audio (pipewire) — necesario para que los atajos wpctl del hyprland.lua funcionen ---
  security.rtkit.enable = true;
  services.pulseaudio.enable = false; # renombrado desde hardware.pulseaudio (confirmado con nix eval real)
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    wireplumber.enable = true;
  };

  # AVRCP "dummy player" -- necesario para que los controles de reproducción
  # (play/pause/skip) de los AirPods (vía LibrePods, ver home/ale/home.nix)
  # funcionen con pipewire/wireplumber. Documentado en linux/README.md de
  # LibrePods como un archivo en ~/.config/wireplumber/wireplumber.conf.d/,
  # pero el módulo de NixOS para wireplumber gestiona su config vía
  # XDG_DATA_DIRS desde el store de Nix (services.pipewire.wireplumber.
  # extraConfig/configPackages), no vía el config-dir tradicional en $HOME --
  # por eso va aquí y no como xdg.configFile en home-manager. Formato
  # verificado contra el ejemplo de bluez del propio módulo en nixpkgs
  # (nixos/modules/services/desktops/pipewire/wireplumber.nix).
  # NO correr mpris-proxy a la vez -- entra en conflicto con esto.
  services.pipewire.wireplumber.extraConfig."51-bluez-avrcp" = {
    "monitor.bluez.properties" = {
      "bluez5.dummy-avrcp-player" = true;
    };
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
    # "hyprland" matchea case-insensitive contra el campo Name= del .desktop
    # de sesión (no el nombre de archivo) -- rastreado hasta
    # greeter_sessions.cpp de noctalia-greeter (discoverSessions +
    # equalsIgnoreCase) y hasta example/hyprland.desktop.in del propio
    # Hyprland (Name=Hyprland). Confirmado, no es una suposición.
    greeter-args = "--session hyprland";
  };

  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    noto-fonts
    noto-fonts-color-emoji # renombrado desde noto-fonts-emoji (confirmado con nix eval real: el nombre viejo tira error duro)
  ];

  environment.systemPackages = with pkgs; [
    kdePackages.kleopatra
    inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.default
    kitty          # terminal usada en hyprland.lua (mainMod+Return)
    brightnessctl  # atajos de brillo en hyprland.lua
  ];
}
