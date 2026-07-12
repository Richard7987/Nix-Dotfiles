{ config, pkgs, lib, inputs, ... }:

{
  imports = [
    inputs.noctalia.homeModules.default
  ];

  home.username = "ale";
  home.homeDirectory = "/home/ale";
  # NUNCA cambies esto tras la primera activación (ver la doc de home-manager
  # sobre home.stateVersion). Ponlo igual al system.stateVersion del host.
  home.stateVersion = "25.05"; # <-- AJUSTAR

  programs.home-manager.enable = true;

  # --- Noctalia: ajustes declarativos vía Nix en vez de TOML a mano ---
  # systemd.enable = false (default) a propósito: Noctalia ya se lanza desde
  # el hook hl.on("hyprland.start", ...) en hyprland.lua -- que es el método
  # que la propia doc de Noctalia documenta para Hyprland. Si además
  # activáramos el servicio systemd (ligado a wayland.systemd.target =
  # "graphical-session.target" por defecto), correríamos el riesgo de que
  # ambos mecanismos lancen Noctalia a la vez -> dos instancias peleando por
  # la barra/IPC. Usa solo uno; el de hyprland.lua es el que no depende de
  # que graphical-session.target se active correctamente.
  programs.noctalia = {
    enable = true;
    settings = {
      theme = {
        mode = "dark";
        source = "builtin";
        builtin = "Catppuccin";
      };
    };
  };

  # --- Hyprland: config en Lua (ver home/ale/hyprland.lua) ---
  xdg.configFile."hypr/hyprland.lua".source = ./hyprland.lua;

  # --- GPG / YubiKey ---
  # Opciones verificadas contra el módulo real de home-manager
  # (programs/gpg.nix y services/gpg-agent.nix).
  programs.gpg = {
    enable = true;
    scdaemonSettings = {
      disable-ccid = true; # por si algún día hay conflicto con el CCID interno, igual que en FreeBSD
      card-timeout = 5;
    };
  };

  services.gpg-agent = {
    enable = true;
    enableSshSupport = true;
    enableZshIntegration = true; # exporta GPG_TTY y corre `updatestartuptty` solo (igual que tu .zshrc en FreeBSD)
    defaultCacheTtl = 600;
    maxCacheTtl = 7200;
    pinentry.package = pkgs.pinentry-qt; # funciona bien en Wayland/Hyprland (a diferencia de pinentry-gtk2 en X11)
  };

  # --- zsh ---
  programs.zsh = {
    enable = true;
    initContent = ''
      # Reinicia pcscd + gpg-agent si la YubiKey deja de responder
      # (equivalente al comando `yubico` que tenías en FreeBSD)
      yubico() {
        doas systemctl restart pcscd.service
        gpgconf --kill gpg-agent
        gpgconf --launch gpg-agent
        gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1
      }
    '';
  };

  # --- git: firma de commits con la YubiKey ---
  programs.git = {
    enable = true;
    userName = "ale";
    userEmail = "anything.la@tuta.com";
    signing = {
      key = "DBD5F61D8A0A14D7";
      format = "openpgp";
      signByDefault = true;
    };
  };

  # --- LibrePods (control de AirPods) ---
  # LibrePods no tiene paquete Nix oficial (proyecto en medio de una reescritura
  # C++/Qt6 -> Rust) y en Linux solo publica AppImages nightly como artifacts de
  # GitHub Actions (requieren sesión de GitHub, sin URL fija que se pueda fijar
  # con hash reproducible) -- no automatizable de forma 100% declarativa.
  # Descarga manual (una vez, y cuando quieras actualizar):
  #   1. https://github.com/kavishdevar/librepods/actions/workflows/ci-linux-rust.yml
  #   2. Entra al run exitoso más reciente -> Artifacts -> descarga el AppImage
  #   3. mkdir -p ~/Applications && mv el .AppImage descargado a
  #      ~/Applications/LibrePods.AppImage && chmod +x ~/Applications/LibrePods.AppImage
  # Después, corre `librepods` (alias de abajo) para lanzarlo.
  xdg.configFile."wireplumber/wireplumber.conf.d/51-bluez-avrcp.conf".text = ''
    # Habilita el reproductor AVRCP "dummy" -- necesario para que los controles
    # de reproducción (play/pause/skip) de los AirPods funcionen con pipewire/
    # wireplumber. Documentado en linux/README.md de LibrePods.
    # NO correr mpris-proxy a la vez -- entra en conflicto con esto.
    monitor.bluez.properties = {
      bluez5.dummy-avrcp-player = true
    }
  '';

  # Reinicia wireplumber tras escribir el conf de arriba para que tome efecto
  # sin necesidad de cerrar sesión. `try-restart` no falla si el servicio no
  # existe/no está corriendo (ej. la primera activación desde una TTY sin
  # sesión gráfica todavía) -- y el `|| true` blinda contra eso igual.
  home.activation.restartWireplumberAvrcp = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run systemctl --user try-restart wireplumber.service 2>/dev/null || true
  '';

  home.packages = with pkgs; [
    yubikey-manager
    appimage-run # para correr el AppImage de LibrePods (ver arriba)
  ];

  home.shellAliases = {
    librepods = "appimage-run ~/Applications/LibrePods.AppImage";
  };
}
