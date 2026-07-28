{ config, pkgs, lib, inputs, ... }:

let
  # SOLO para sage (ver flake.nix, input nixpkgs-stable): nixos-26.05 en vez
  # de unstable, porque sage es un build pesado (~1700 archivos Cython) que
  # en unstable puede pisar una ventana sin caché de Hydra por cualquier
  # bump reciente (pasó en vivo el 2026-07-27: nixpkgs#545171, sagelib roto
  # por el bump a Python 3.14, arreglado un día después pero mientras tanto
  # implicaba compilar todo a mano). Stable tiene builds de Hydra mucho más
  # estables/cacheados y encima no carga Python 3.14 todavía, evitando esa
  # clase de regresión.
  pkgsStable = import inputs.nixpkgs-stable {
    inherit (pkgs.stdenv.hostPlatform) system;
    config.allowUnfree = true; # por consistencia con nixpkgs.config.allowUnfree de hosts/ale/configuration.nix, aunque sage no lo necesita
  };
in
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

      # --- Plugin screen_recorder: capturar por monitor en vez de portal ---
      # Con el default (video_source = "portal") gpu-screen-recorder falla en
      # este equipo: "Recording failed" en pantalla, y en
      # ~/.cache/noctalia/noctalia.log aparece
      # "gsr_pipewire_video_create_egl_image_with_fallback: failed to create
      # egl image with modifier ..." seguido de "no more input formats" y
      # timeout de negociación PipeWire -- problema conocido de
      # gpu-screen-recorder + portal en Nvidia propietario (PRIME sync,
      # ver modules/graphics.nix). "focused" pasa -w <monitor> en vez de
      # -w portal, capturando el output directo vía wlroots sin depender del
      # portal/PipeWire (confirmado en recorder_service.luau del plugin).
      plugin_settings."noctalia/screen_recorder".video_source = "focused";
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

      # --- Idle: bloqueo/apagado de pantalla/suspensión por inactividad ---
      # CORRECCIÓN: la ronda anterior agregó services.hypridle (systemd,
      # externo) asumiendo que Noctalia no tenía nada propio. Falso --
      # Noctalia trae su propio IdleManager nativo (src/idle/, sobre
      # ext-idle-notify-v1, confirmado leyendo el fuente real de
      # noctalia-shell 5.0.0) con exactamente este mismo propósito, vía
      # [idle.behavior.*] en TOML (action = lock|screen_off|suspend|
      # lock_and_suspend|command, ver example.toml del paquete). Usar el
      # externo duplicaba el trabajo Y competía por la interfaz DBus
      # org.freedesktop.ScreenSaver que Noctalia ya registra (confirmado en
      # vivo: "[ERR] Another service is already providing the
      # org.freedesktop.ScreenSaver interface" en el log de hypridle) --
      # ver NOTES.md. Se saca hypridle (y su arranque en hyprland.lua) y se
      # usa esto en su lugar: mismos timeouts, sin segundo daemon.
      idle = {
        behavior = {
          lock = {
            timeout = 300; # 5 min sin actividad -> bloquear
            action = "lock";
            enabled = true;
          };
          "screen-off" = {
            timeout = 330; # ~30s después del lock -> apagar pantalla (batería del laptop)
            action = "screen_off";
            enabled = true;
          };
          suspend = {
            timeout = 900; # 15 min sin actividad -> suspender
            action = "suspend"; # lock_before_suspend default = true, ya bloquea antes de suspender
            enabled = true;
          };
        };
      };

      # --- Screenshots ---
      # No hacía falta agregar grim/slurp: Noctalia trae su propio
      # ScreenshotService nativo (src/capture/, IPC "screenshot-region" /
      # "screenshot-fullscreen", confirmado en el fuente). Los defaults de
      # ScreenshotConfig ya sirven (saveToFile=true a ~/Pictures,
      # copyToClipboard=true, freezeScreen=true), así que no se pisa nada
      # acá -- solo faltan los binds, agregados en hyprland.lua.

      # --- Clipboard ---
      # Tampoco hacía falta cliphist: shell.clipboard_enabled ya es true por
      # default (historial + panel "clipboard" nativos, confirmado en
      # config_types.h). Solo faltaba el bind para abrir el panel, agregado
      # en hyprland.lua (mainMod+P).
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

  # --- delta: diffs con resaltado de sintaxis (got diff) ---
  # got produce diff unificado estándar (igual que git diff/diff -u), así que
  # delta lo entiende sin que le importe que el VCS acá sea got y no git --
  # confirmado, delta solo lee el formato del diff, no invoca git.
  # Sin PAGER=delta a propósito: got (a diferencia de git) no invoca ningún
  # pager por su cuenta -- confirmado con `strings $(which got) | grep -i
  # pager` (nada) y el man page (tampoco lo menciona) -- así que esa variable
  # no le serviría de nada a got diff, y de paso afectaría a CUALQUIER otro
  # programa que respete $PAGER (man, systemctl status, journalctl) sin
  # ningún beneficio a cambio. En vez de eso, la función `gd` de abajo
  # (programs.zsh.initContent) pipea `got diff` a delta explícitamente.
  # paquete delta declarado más abajo, junto al resto de home.packages (dos
  # asignaciones de home.packages en el mismo archivo chocan -- Nix tira
  # "attribute already defined", no las mergea solas como sí hace el sistema
  # de módulos entre archivos distintos).
  xdg.configFile."delta/config".text = ''
    [delta]
        navigate = true
        side-by-side = true
        line-numbers = true
        syntax-theme = gruvbox-dark
  '';

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

      # gotd / gotl: `got diff` / `got log -p` a través de delta. got (a
      # diferencia de git) no invoca ningún pager por su cuenta -- confirmado
      # con `strings $(which got) | grep -i pager` (nada), el man page
      # (tampoco lo menciona), y el propio ejemplo del man page usa
      # `got diff | less` a mano -- así que hace falta pipearlo siempre.
      # "$@" para poder pasarle los mismos argumentos que aceptan got diff /
      # got log (revisiones, -c, un path).
      #
      # NO se llaman "gd"/"gl": el plugin "git" de oh-my-zsh (arriba) ya
      # define alias gd='git diff' y alias gl='git pull' -- un alias tapa a
      # una función del mismo nombre en zsh (la expansión de alias corre
      # antes de resolver funciones), así que gd/gl acá nunca se hubieran
      # ejecutado. gotd/gotl no chocan con nada del plugin git.
      gotd() {
        got diff "$@" | delta
      }

      gotl() {
        got log -p "$@" | delta
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
    delta # diffs con resaltado (got diff / git diff) -- ver PAGER=delta y xdg.configFile."delta/config" más arriba
    yubikey-manager
    (callPackage ../../pkgs/librepods.nix { })
    (python3Packages.callPackage ../../pkgs/clamui.nix { }) # GUI de ClamAV -- clamav en sí va en configuration.nix (services.clamav), clamui solo invoca `clamscan` por $PATH
    pkgsStable.sage # sistema matemático (no es un IDE -- CLI + kernel Jupyter propio). Paquete oficial de nixpkgs, no hace falta derivación propia como clamui/librepods.
      # pkgsStable (nixos-26.05, no el nixpkgs/unstable de arriba) a propósito -- ver el comentario del `let` más arriba.
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
    # IntelliJ IDEA Ultimate -- paquete directo de nixpkgs, no Toolbox:
    # Toolbox baja binarios fuera del store y se autoactualiza por su
    # cuenta, no encaja con el modelo declarativo de este repo (mismo
    # motivo por el que LibrePods se compila de fuente en vez de usar un
    # AppImage, ver pkgs/librepods.nix). Requiere licencia/login JetBrains
    # la primera vez que se abre. allowUnfree ya está en true a nivel
    # sistema (hosts/ale/configuration.nix, por Nvidia/Steam) y
    # useGlobalPkgs = true lo hereda acá, así que no hace falta nada extra.
    #
    # Wrapper sobre bin/idea para arreglar el preview de Markdown (y
    # cualquier otra vista basada en JCEF -- el navegador embebido de las
    # IDEs JetBrains, Chromium Embedded Framework). Diagnosticado en vivo
    # (2026-07-27): el preview se queda en blanco porque
    # jcef_helper/libcef.so (adentro de idea/plugins/jcef-plugin/jcef/)
    # fallan con "error while loading shared libraries" contra ~19 libs
    # (nspr/nss, dbus, at-spi2 (atk), cups, la pila de X11, mesa/gbm,
    # expat, xkbcommon, cairo, pango) -- confirmado corriendo
    # `ldd .../jcef_helper` a mano contra el store real. Es un gap real de
    # nixpkgs, no de esta config: pkgs/applications/editors/jetbrains/
    # ides/idea.nix solo agrega `zlib` a extraLdPath, e incluso el propio
    # readme.md de nixpkgs para paquetes jetbrains tiene un TODO sin
    # resolver sobre JCEF ("use chromium stuff built by nixpkgs for
    # jcef?"). No se puede simplemente re-wrappear bin/idea con
    # overrideAttrs porque colisiona con el nombre que makeWrapper ya usa
    # internamente (.idea-wrapped, creado por el wrapProgram original) --
    # symlinkJoin + un wrapper nuevo evita eso del todo, sin tocar los
    # archivos internos del paquete original. share/applications/*.desktop
    # y los íconos quedan igual (symlinkeados desde el paquete real), y
    # como el .desktop usa `Exec=idea` (comando pelado, no ruta absoluta),
    # el launcher de Noctalia agarra este wrapper solo por estar antes en
    # $PATH -- sin tocar nada del .desktop.
    (pkgs.symlinkJoin {
      name = "idea-jcef-fix";
      paths = [ pkgs.jetbrains.idea ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        rm "$out/bin/idea"
        makeWrapper "${pkgs.jetbrains.idea}/bin/idea" "$out/bin/idea" \
          --prefix LD_LIBRARY_PATH : "${pkgs.lib.makeLibraryPath (with pkgs; [
            nspr nss dbus at-spi2-core cups alsa-lib
            libx11 libxcomposite libxdamage libxext libxfixes libxrandr libxcb
            libgbm expat libxkbcommon cairo pango
          ])}"
      '';
      meta = pkgs.jetbrains.idea.meta // { mainProgram = "idea"; };
    })
    libreoffice-fresh # suite completa (Writer/Calc/Impress/Draw/Base/Math) --
      # "fresh" (26.2.x, última rama) en vez de "still" (25.8.x, LTS): sin
      # motivo para preferir la rama LTS acá.
    hunspellDicts.es_MX # diccionario ortográfico español de México, para que
      # LibreOffice lo detecte al corregir. No hace falta wiring extra: el
      # wrapper real de libreoffice (pkgs/applications/office/libreoffice/
      # wrapper.nix) ya recorre $NIX_PROFILES buscando */share/hunspell y
      # arma $DICPATH solo -- alcanza con que el paquete esté instalado acá
      # (home.packages cae en el profile del usuario, que sí está en
      # $NIX_PROFILES). El idioma default del documento ya sale es_MX porque
      # LibreOffice hereda el locale del sistema (i18n.defaultLocale en
      # hosts/ale/configuration.nix), así que no hay que tocar nada dentro
      # de la UI tampoco.
    # dependencia del plugin oficial "screen_recorder" de Noctalia
    # (noctalia-dev/official-plugins) -- el plugin solo hace de wrapper/IPC,
    # busca este binario en PATH. El derivation de nixpkgs ya wrappea
    # LD_LIBRARY_PATH con /run/opengl-driver/lib, que trae las libs NVENC
    # de Nvidia gracias a hardware.graphics.enable + hardware.nvidia.* de
    # modules/graphics.nix. El portal (xdg-desktop-portal-hyprland) ya lo
    # activa programs.hyprland.enable solo. El plugin en sí NO se declara
    # acá -- Noctalia v5 lo baja y activa en runtime (ver instrucción abajo).
    #
    # SÍ hace falta un override puntual acá: environment.sessionVariables.
    # LIBVA_DRIVER_NAME = "nvidia" (modules/graphics.nix) fuerza VAAPI a
    # cargar el driver de Nvidia sin importar qué dispositivo se abra.
    # video_source=focused (ver programs.noctalia.settings.plugin_settings
    # más arriba) hace que gpu-screen-recorder capture vía KMS en el nodo
    # que de verdad maneja la pantalla interna en modo PRIME sync --
    # /dev/dri/renderD128, la iGPU Intel -- y ahí esa variable forzada rompe
    # vaInitialize (confirmado en vivo: "vaInitialize failed" /
    # "failed to query supported video codecs for device
    # /dev/dri/renderD128" en el log de Noctalia). El wrapper solo
    # desactiva esa variable para este binario puntual -- no toca el env
    # global, así que el resto de las apps (navegador, mpv) siguen usando
    # VAAPI de Nvidia como se pretendía.
    (pkgs.gpu-screen-recorder.overrideAttrs (old: {
      nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.makeWrapper ];
      postFixup = (old.postFixup or "") + ''
        wrapProgram $out/bin/gpu-screen-recorder --unset LIBVA_DRIVER_NAME
      '';
    }))
  ];
}
