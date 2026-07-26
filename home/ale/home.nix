{ config, pkgs, lib, inputs, ... }:

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

  # --- Carpetas XDG estándar ---
  # Antes solo existían Pictures/Videos/Downloads creadas a mano (más una
  # "Descargas" duplicada, probablemente de una app que leyó el locale
  # es_MX). Declararlas acá evita que queden huérfanas fuera del repo y
  # que se vuelvan a duplicar. Nombres en inglés a propósito, para no
  # romper Pictures/Videos/Downloads que ya existen y tienen contenido.
  xdg.userDirs = {
    enable = true;
    createDirectories = true;
    desktop = "${config.home.homeDirectory}/Desktop";
    documents = "${config.home.homeDirectory}/Documents";
    download = "${config.home.homeDirectory}/Downloads";
    music = "${config.home.homeDirectory}/Music";
    pictures = "${config.home.homeDirectory}/Pictures";
    publicShare = "${config.home.homeDirectory}/Public";
    templates = "${config.home.homeDirectory}/Templates";
    videos = "${config.home.homeDirectory}/Videos";
  };

  # --- Cursor ---
  # Sin esto, Hyprland cae a su cursor propio por defecto (el logo de
  # Hyprland) -- no hay ningún theme de cursor instalado/declarado.
  # hyprcursor.enable = true exporta HYPRCURSOR_THEME/HYPRCURSOR_SIZE (única
  # forma de que Hyprland use un theme real en vez de su fallback, confirmado
  # contra el módulo real home-manager, modules/config/home-cursor.nix).
  # gtk.enable = true de paso para que Nautilus/Kleopatra/etc. usen el mismo
  # cursor. "Bibata-Modern-Amber" -- tonos cálidos, combina con Gruvbox.
  # Necesario para que pointerCursor.gtk.enable de abajo aplique de verdad --
  # confirmado que solo gestiona gtk-3.0/settings.ini (cursor-theme-name),
  # NO gtk.css (eso solo pasa si se setea gtk.gtk3.extraCss, que no hacemos)
  # -- no choca con el gtk.css que Noctalia ya escribe en runtime.
  gtk.enable = true;

  home.pointerCursor = {
    enable = true;
    package = pkgs.bibata-cursors;
    name = "Bibata-Modern-Amber";
    size = 24;
    gtk.enable = true;
    hyprcursor.enable = true;
  };

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
    # El cherry-pick del fix de password de CalDAV (pkgs/noctalia-patched.nix)
    # ya fue mergeado en upstream desde noctalia 5.0.0 (2026-07-26, ver
    # NOTES.md) -- el paquete default del flake ya trae el fix, sin override.
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

  # --- hypridle: bloqueo/apagado de pantalla/suspensión automáticos por
  # inactividad ---
  # Noctalia no trae su propia pantalla de bloqueo con temporizador de idle;
  # solo expone el comando manual "noctalia msg session lock" (el mismo que
  # ya usa mainMod+L en hyprland.lua, confirmado que funciona contra la doc
  # de Noctalia). hypridle solo dispara ESE mismo comando por inactividad, en
  # vez de agregar un segundo mecanismo de lock (ej. hyprlock) que compita
  # con el que ya está confirmado.
  # El módulo de home-manager solo escribe hypridle.conf y crea el
  # systemd.user.service -- lo arranca vía WantedBy=graphical-session.target,
  # que en este setup NO se activa (mismo problema ya documentado arriba para
  # Noctalia). Por eso el arranque real va en hyprland.lua, junto al de
  # Noctalia (ver hl.on("hyprland.start", ...)), con `systemctl --user start`
  # para reusar el unit generado (Restart=always incluido) en vez de otro
  # loop manual.
  services.hypridle = {
    enable = true;
    settings = {
      general = {
        lock_cmd = "noctalia msg session lock";
        before_sleep_cmd = "noctalia msg session lock";
        after_sleep_cmd = "hyprctl dispatch dpms on";
      };
      listener = [
        {
          timeout = 300; # 5 min sin actividad -> bloquear
          on-timeout = "noctalia msg session lock";
        }
        {
          timeout = 330; # ~30s después del lock -> apagar pantalla (batería del laptop)
          on-timeout = "hyprctl dispatch dpms off";
          on-resume = "hyprctl dispatch dpms on";
        }
        {
          timeout = 900; # 15 min sin actividad -> suspender
          on-timeout = "systemctl suspend";
        }
      ];
    };
  };

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
    # Sin "theme" acá a propósito -- el prompt real lo pone Powerlevel10k
    # (fuente más abajo, en initContent), no un theme de oh-my-zsh.
    oh-my-zsh = {
      enable = true;
      plugins = [ "git" "sudo" ];
    };
    # fzf-tab -- menú interactivo con fuzzy-search en el Tab (en vez de la
    # lista plana de zsh). Va acá (programs.zsh.plugins, no oh-my-zsh.plugins
    # porque no es un plugin bundled de oh-my-zsh) para que se sourcee vía el
    # mecanismo genérico de home-manager, que carga a mkOrder 900 -- DESPUÉS
    # del compinit que corre oh-my-zsh (mkOrder 800, ver "source $ZSH/oh-my-
    # zsh.sh" en modules/programs/zsh/plugins/oh-my-zsh.nix). Confirmado
    # contra el README real de fzf-tab: exige cargarse "after compinit, but
    # before plugins which will wrap widgets" (zsh-autosuggestions, fast-
    # syntax-highlighting) -- ver el bloque de autosuggestions más abajo.
    plugins = [
      {
        name = "fzf-tab";
        src = pkgs.zsh-fzf-tab;
        file = "share/fzf-tab/fzf-tab.plugin.zsh";
      }
    ];
    # zsh-syntax-highlighting -- colorea el comando mientras lo escribís:
    # verde si el comando/alias/función existe, rojo si no. Opción nativa de
    # home-manager (a diferencia de autosuggestion.enable, esta SÍ sourcea en
    # mkOrder 1200 por defecto -- confirmado en modules/programs/zsh/
    # default.nix -- que ya cae después de fzf-tab (900), como exige su
    # README, sin necesitar ningún mkOrder manual).
    syntaxHighlighting.enable = true;
    initContent = lib.mkMerge [
      # zsh-autosuggestions -- sourceado a mano (NO con la opción nativa
      # programs.zsh.autosuggestion.enable) porque esa opción fija su propio
      # mkOrder en 700, es decir ANTES del compinit de oh-my-zsh (800) y
      # ANTES de fzf-tab (900) -- el orden opuesto al que exige el README de
      # fzf-tab (compinit -> fzf-tab -> autosuggestions). mkOrder 950 acá
      # deja la secuencia real: compinit (800) -> fzf-tab (900) ->
      # autosuggestions (950) -> resto del initContent (1000, sin envolver
      # -- ver comentario de p10k debajo).
      (lib.mkOrder 950 ''
        source ${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions/zsh-autosuggestions.plugin.zsh
      '')
      ''
      # Powerlevel10k -- bloques de color sólidos + wizard interactivo de
      # configuración (fuentes/símbolos/una o dos líneas/conectado o no) la
      # primera vez que abras una terminal, porque a propósito NO se pre-crea
      # ~/.p10k.zsh: p10k detecta que no existe y lanza `p10k configure` solo.
      # Corre después de oh-my-zsh (mismo bloque de initContent, se concatena
      # con orden por defecto 1000, y el de oh-my-zsh usa mkOrder 800 -- más
      # bajo sale primero) para pisar cualquier prompt que oh-my-zsh hubiera
      # puesto. gitstatus (paquete separado, da el binario gitstatusd) es
      # necesario en PATH para el estado de git rápido -- sin él, el plugin
      # de p10k intentaría bajarlo en runtime, cosa que falla en un sandbox
      # de Nix sin red.
      source ${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k/powerlevel10k.zsh-theme

      # Config generada por `p10k configure` -- copiada al repo
      # (home/ale/p10k.zsh) y declarada vía home.file más abajo, para que
      # sea reproducible igual que el resto de la config. Si vuelves a
      # correr `p10k configure`, el wizard va a decir de nuevo que no puede
      # escribir ~/.zshrc (normal, es un symlink de home-manager) -- elige
      # "n", y después copia el ~/.p10k.zsh que sí actualiza a
      # home/ale/p10k.zsh para que el cambio quede permanente.
      source ~/.p10k.zsh

      # Reinicia pcscd + gpg-agent si la YubiKey deja de responder
      # (equivalente al comando `yubico` que tenías en FreeBSD)
      yubico() {
        sudo systemctl restart pcscd.service
        gpgconf --kill gpg-agent
        gpgconf --launch gpg-agent
        gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1
      }

      # nixos-update: flujo completo de actualización del sistema. Este
      # equipo se despliega vía flake (/nixdots#ale), NO vía nix-channel --
      # `nixos-rebuild switch --upgrade` a secas falla acá ("file
      # 'nixos-config' was not found in the Nix search path", ver NOTES.md
      # 2026-07-22) porque no hay NIX_PATH nixos-config. El subshell con
      # `set -e` corta en el primer error (ej. build roto) sin aplicar
      # switch ni tocar el cwd de la terminal interactiva.
      # /nixdots es un work tree de got (sin .git, ver "Migración a got
      # puro" en NOTES.md 2026-07-22) -- got commit no soporta firma, así
      # que este commit de flake.lock queda sin firmar (a diferencia de los
      # commits manuales de antes con git commit -S).
      #
      # Sin argumentos actualiza TODOS los inputs a la vez (comportamiento
      # de siempre). Pasándole nombres de inputs (ej. `nixos-update nixpkgs`)
      # actualiza solo esos -- útil para no mover inputs que no hacía falta
      # tocar y así no perder el cache-hit de noctalia.cachix.org /
      # psysonic.cachix.org en builds que de otra forma no habrían cambiado
      # (ver auditoría 2026-07-26 en NOTES.md).
      nixos-update() {
        (
          set -e
          cd /nixdots
          sudo nix flake update "$@"
          sudo nixos-rebuild build --flake .#ale
          sudo nixos-rebuild switch --flake .#ale
          if [ -n "$(got status flake.lock)" ]; then
            got commit -m "Actualiza flake.lock" flake.lock
          fi
        )
      }

      # vpn up / vpn down: alterna a mano el exit node de Mullvad sin tocar
      # la config declarativa. El oneshot de systemd en modules/tailscale.nix
      # (tailscale-exit-node) ya lo deja fijado en cada arranque, así que esto
      # es solo para apagarlo un rato (ej. necesitas tu IP real para algo) y
      # volver a prenderlo después, sin esperar un reboot ni un rebuild
      # switch. Sin pedir password: sudoers en modules/yubikey.nix ya permite
      # `tailscale` con cualquier argumento (NOPASSWD) para el usuario ale.
      vpn() {
        case "$1" in
          up)
            sudo tailscale set --exit-node=mullvad-exit --exit-node-allow-lan-access=true
            ;;
          down)
            sudo tailscale set --exit-node=
            ;;
          *)
            echo "uso: vpn up|down"
            return 1
            ;;
        esac
      }

      # pfetch al final: después de p10k (ya cargado arriba) para no
      # imprimir nada antes de que el instant prompt se muestre -- si igual
      # sale una advertencia de "console output during initialization" (el
      # wizard eligió modo Verbose), es solo informativa, no rompe nada.
      pfetch
      ''
    ];
  };

  home.file.".p10k.zsh".source = ./p10k.zsh;

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
  # Ya no depende de bajar el AppImage nightly a mano -- se compila de fuente
  # (ver pkgs/librepods.nix para el porqué y las verificaciones hechas).
  # (El fix de AVRCP para play/pause/skip va en modules/desktop.nix, vía
  # services.pipewire.wireplumber.extraConfig -- no aquí. Ver el comentario
  # ahí para el porqué.)

  home.packages = with pkgs; [
    yubikey-manager
    (callPackage ../../pkgs/librepods.nix { })
    gitstatus # da el binario gitstatusd que necesita Powerlevel10k (ver programs.zsh)
    meslo-lgs-nf # Nerd Font que recomienda p10k para sus glifos/iconos
    pfetch # info del sistema al abrir terminal (ver programs.zsh.initContent)
    fzf # binario que fzf-tab invoca para el menú interactivo del Tab (ver programs.zsh.plugins)
    weechat # cliente IRC de terminal -- sin módulo declarativo en home-manager
      # (no hay `programs.weechat`, se confirmó buscando en el source real del
      # input), así que la config de plugins/scripts queda a mano dentro de
      # weechat (`/script install ...`), no versionada en este repo.
    btop # monitor de recursos en terminal -- Noctalia ya trae un template de
      # color built-in para btop (theme.templates, ver comentario más arriba),
      # pero el paquete en sí no estaba instalado; sin él, ese template no
      # tenía nada a qué aplicarse.
    obsidian # notas locales en Markdown -- paquete directo de nixpkgs, sin
      # módulo declarativo propio (guarda su config/vaults dentro de cada
      # vault, no hay nada que declarar acá).
    jetbrains.idea # IntelliJ IDEA Ultimate -- paquete directo de nixpkgs, no
      # Toolbox: Toolbox baja binarios fuera del store y se autoactualiza por
      # su cuenta, no encaja con el modelo declarativo de este repo (mismo
      # motivo por el que LibrePods se compila de fuente en vez de usar un
      # AppImage, ver pkgs/librepods.nix). Requiere licencia/login JetBrains
      # la primera vez que se abre. allowUnfree ya está en true a nivel
      # sistema (hosts/ale/configuration.nix, por Nvidia/Steam) y
      # useGlobalPkgs = true lo hereda acá, así que no hace falta nada extra.
    gpu-screen-recorder # dependencia del plugin oficial "screen_recorder" de Noctalia
      # (noctalia-dev/official-plugins) -- el plugin solo hace de wrapper/IPC,
      # busca este binario en PATH. El derivation de nixpkgs ya wrappea
      # LD_LIBRARY_PATH con /run/opengl-driver/lib, que trae las libs NVENC
      # de Nvidia gracias a hardware.graphics.enable + hardware.nvidia.* de
      # modules/graphics.nix -- no hace falta ningún override extra. El
      # portal (xdg-desktop-portal-hyprland) ya lo activa
      # programs.hyprland.enable solo. El plugin en sí NO se declara acá --
      # Noctalia v5 lo baja y activa en runtime (ver instrucción abajo).
  ];
}
