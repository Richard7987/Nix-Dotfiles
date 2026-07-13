{ config, pkgs, inputs, ... }:

{
  imports = [
    inputs.noctalia.homeModules.default
  ];

  home.username = "ale";
  home.homeDirectory = "/home/ale";
  # NUNCA cambies esto tras la primera activación (ver la doc de home-manager
  # sobre home.stateVersion). Ponlo igual al system.stateVersion del host.
  home.stateVersion = "26.05";

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
  # Paquete Nix real de wallpapers (github:AngelJumbo/gruvbox-wallpapers,
  # categoría "default" = las 554 imágenes de todas las categorías, ~1.4GB) --
  # instalado declarativamente vía home.file en vez de bajarlos a mano.
  # recursive = true: symlinkea archivo por archivo (no la carpeta entera
  # como una unidad), tal cual lo documenta el propio README del repo.
  home.file."Pictures/Wallpapers/gruvbox" = {
    source = inputs.gruvbox-wallpapers.packages.${pkgs.stdenv.hostPlatform.system}.default;
    recursive = true;
  };

  programs.noctalia = {
    enable = true;
    settings = {
      theme = {
        mode = "dark";
        source = "builtin";
        builtin = "Gruvbox";
        # "yazi" es el único gestor de archivos con template oficial de color
        # de Noctalia (confirmado con `noctalia theme --list-templates` --
        # está en community templates, no built-in). builtin_ids (gtk3/gtk4/
        # hyprland/kitty/btop) ya vienen activos por default, no hace falta
        # declararlos.
        templates.community_ids = [ "yazi" ];
      };
      wallpaper.directory = "${config.home.homeDirectory}/Pictures/Wallpapers/gruvbox";
      # Sin esto NO hay ningún agente de polkit corriendo (Hyprland/gamemode
      # solo activan el daemon de polkit, no un agente gráfico) -- acciones
      # con privilegios de apps GUI (ej. NetworkManager guardando una
      # contraseña wifi) fallarían en silencio sin diálogo que las autorice.
      # Noctalia trae su propio agente (src/shell/polkit/), pero viene
      # apagado por defecto (polkit_agent = false en example.toml).
      shell.polkit_agent = true;
      # shell.lang: sin setear a propósito. i18n_service.cpp cae a
      # $LANG/$LC_ALL/$LC_MESSAGES si no hay preferencia explícita, y ya
      # tenemos i18n.defaultLocale = "es_MX.UTF-8" a nivel de sistema
      # (hosts/ale/configuration.nix) -- confirmado que existe catálogo
      # es.json en assets/translations/, así que la UI sale en español sola.
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
      # STRING, no entero: el tipo de scdaemonSettings es "string or bool or
      # list of string" (confirmado con nix eval real -- con un entero acá
      # fallaba TODO el build: "is not of type `string or boolean or list of
      # string'"). El texto generado sale igual: "card-timeout 5".
      card-timeout = "5";
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
        sudo systemctl restart pcscd.service
        gpgconf --kill gpg-agent
        gpgconf --launch gpg-agent
        gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1
      }
    '';
  };

  # --- git: firma de commits con la YubiKey ---
  programs.git = {
    enable = true;
    # settings.user.* (no userName/userEmail sueltos): renombrado, confirmado
    # con nix eval real ("has been renamed to `programs.git.settings.user.*'").
    settings.user = {
      name = "ale";
      # Debe coincidir con el UID de la llave GPG (ale_bnes@tuta.com, ver
      # "Login data" en `gpg --card-status`) -- si no coincide, Forgejo
      # verifica la firma correctamente pero la marca como "usuario no
      # fiable que no coincide con el colaborador" porque el email del
      # commit no matchea ningún email verificado de la cuenta.
      email = "ale_bnes@tuta.com";
    };
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
  # (El fix de AVRCP para play/pause/skip va en modules/desktop.nix, vía
  # services.pipewire.wireplumber.extraConfig -- no aquí. Ver el comentario
  # ahí para el porqué.)

  home.packages = with pkgs; [
    yubikey-manager
    appimage-run # para correr el AppImage de LibrePods (ver arriba)
  ];

  home.shellAliases = {
    librepods = "appimage-run ~/Applications/LibrePods.AppImage";
  };
}
