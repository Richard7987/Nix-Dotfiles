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

  # debugpy agregado al entorno Python de Sage -- sin esto, el debugger de
  # notebooks de IDEA/PyCharm no puede conectarse al kernel (necesita
  # debugpy corriendo del lado del kernel para breakpoints/step; confirmado
  # en vivo: `sage --python3 -c "import debugpy"` fallaba con
  # ModuleNotFoundError antes de este override). requireSageTests = false
  # -- sin esto, nixpkgs vuelve a correr TODA la suite de doctests de Sage
  # (miles de tests, 30+ min) cada vez que cambia el derivation de "sage"
  # por cualquier motivo (como agregar un paquete acá) -- confirmado en
  # vivo, se probó primero sin este flag y tardaba demasiado.
  sageWithDebug = pkgsStable.sage.override {
    extraPythonPackages = ps: [ ps.debugpy ];
    requireSageTests = false;
  };

  # Ruta al kernelspec de sagemath, para que molten-nvim (que corre bajo el
  # Python propio de Neovim, no el de Sage) también lo descubra. `sage`
  # (el wrapper final) ya trae esto embebido como un `--prefix JUPYTER_PATH`
  # de makeWrapper -- en vez de reconstruir a mano el mismo
  # `pkgs.jupyter-kernel.create {...}` que arma package.nix de sage
  # (duplicaría lógica interna y se desincroniza fácil), se extrae
  # directo del wrapper ya construido leyendo su contenido. Así se
  # mantiene sincronizado solo con cualquier `sageWithDebug` que termine
  # resolviendo, sin ningún hash de store hardcodeado.
  sageJupyterPath =
    let
      wrapperContent = builtins.readFile "${sageWithDebug}/bin/sage";
      m = builtins.match ".*JUPYTER_PATH=.(/nix/store/[a-z0-9]+-jupyter-kernels)..*" wrapperContent;
    in
    if m == null then
      throw "No se pudo extraer JUPYTER_PATH del wrapper de sage -- ¿cambió el formato del wrapper?"
    else
      builtins.head m;
in
{
  imports = [
    inputs.noctalia.homeModules.default
    inputs.lazyvim.homeManagerModules.default
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

  # --- herdr (multiplexor de agentes en terminal, paquete más abajo en
  # home.packages) --- "gruvbox" es un theme nativo (confirmado corriendo
  # `herdr --default-config` en vivo), mismo criterio que el resto del
  # setup. default_shell = zsh explícito -- sin esto cae a $SHELL, que ya
  # es zsh igual (ver users.users.ale.shell en hosts/ale/configuration.nix),
  # pero mejor no depender de que la variable esté seteada igual en todos
  # los contextos donde se lance herdr.
  xdg.configFile."herdr/config.toml".text = ''
    onboarding = false

    [theme]
    name = "gruvbox"

    [terminal]
    default_shell = "zsh"
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
    sageWithDebug # sistema matemático (no es un IDE -- CLI + kernel Jupyter propio). Paquete oficial de nixpkgs (con debugpy agregado, ver el `let` más arriba), no hace falta derivación propia como clamui/librepods.
      # pkgsStable (nixos-26.05, no el nixpkgs/unstable de arriba) a propósito -- ver el comentario del `let` más arriba.
    # Wrapper para que IntelliJ/PyCharm puedan usar el kernel de Sage en
    # notebooks Jupyter SIN pelear con el server manual. Diagnosticado en
    # vivo (2026-07-27): el soporte nativo de notebooks de la IDE lanza su
    # propio server Jupyter invocando DIRECTO el binario python3 que
    # elegiste como intérprete del proyecto (`python3 -m jupyterlab ...`),
    # no el comando `sage` -- así que se salta por completo `sage-env` (el
    # script que agrega Singular/Maxima/GAP/etc. al $PATH antes de correr
    # nada). Resultado: el kernel "sagemath" muere al arrancar con
    # "singular is not available" apenas el notebook hace `import
    # sage.all`, aunque correr un .sage vía el plugin SageMath (que sí
    # invoca `sage` de verdad) funciona perfecto.
    #
    # `sage --python3 [...]` es la forma oficial de correr el Python real
    # de Sage con sage-env ya sourceado (confirmado: `sage --python3
    # --version` imprime "Python 3.13.14", igual que un python3 normal, y
    # `sys.executable` adentro apunta al python3 real) -- así que este
    # wrapper solo reenvía todos los argumentos ahí. Se hace pasar por un
    # intérprete Python cualquiera ante la IDE (podés elegirlo como
    # "System Interpreter" del proyecto igual que el python3 crudo), pero
    # cualquier proceso que lance por dentro (el kernel Jupyter incluido)
    # hereda el $PATH ya correcto.
    (pkgs.writeShellScriptBin "sage-python3" ''
      exec ${sageWithDebug}/bin/sage --python3 "$@"
    '')
    herdr # multiplexor de agentes (Claude Code, etc.) para la terminal --
      # NO reemplaza a kitty (que sigue siendo la terminal, ver
      # modules/desktop.nix), corre COMO programa dentro de ella, similar a
      # tmux/zellij pero con detección de estado de agentes (blocked/
      # working/done). Config en xdg.configFile más abajo.
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
    zed-editor # IDE con soporte nativo de ACP (Zed lo creó) -- Claude Code
      # corre ahí sin plugin de por medio, a diferencia de Neovim/agentic.nvim.
      # Se activa desde la propia UI (menú "+" del Agent Panel), usa el
      # `claude-code` ya instalado a nivel de sistema (hosts/ale/
      # configuration.nix) vía $PATH, sin configuración adicional.
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

  # --- Server de Jupyter Lab con kernel de Sage, persistente ---
  # Diagnosticado en vivo (2026-07-27): el modo "IDE-Managed" de la
  # integración nativa de notebooks de IDEA falla en el handshake de
  # websocket con el kernel ("Failed to create a web socket") aunque el
  # server y el kernel arrancan bien -- confirmado que el bug es del
  # cliente de websocket de la IDE, no del server: una conexión de
  # websocket hecha a mano desde Python al mismo server conecta sin
  # problema. La vuelta es apuntar la IDE a un server YA corriendo
  # ("Running Local Server" en Settings -> Tools -> Jupyter -> Jupyter
  # Servers) en vez de dejar que la IDE lance el suyo -- pero eso requiere
  # que algo mantenga ese server vivo (arrancarlo a mano no sobrevive un
  # logout/reinicio, y cada arranque genera un token nuevo, lo que rompe
  # la config guardada en la IDE). Este servicio systemd de usuario
  # resuelve las dos cosas: arranca solo en cada login y usa un token fijo
  # para que la config de "Running Local Server" quede estable para
  # siempre.
  #
  # --notebook-dir apunta a IdeaProjects/Jupyter_Notebooks a propósito
  # (no $HOME entero): el server expone un navegador de archivos por HTTP
  # con auth por token -- acotarlo a esta carpeta evita exponer el resto
  # del $HOME sin necesidad.
  #
  # Token fijo generado una vez con `python3 -c "import secrets;
  # print(secrets.token_hex(24))"` -- no es un secreto de verdad crítico
  # (el server solo escucha en 127.0.0.1, --ip=127.0.0.1, nunca sale a la
  # red), pero igual no queda hardcodeado en texto plano más de lo
  # necesario: solo lo usa este servicio y la config de "Running Local
  # Server" en la IDE (Settings -> Tools -> Jupyter -> Jupyter Servers),
  # ninguna de las dos versionadas en git/got.
  systemd.user.services.sage-jupyterlab = {
    Unit = {
      Description = "Jupyter Lab con kernel de Sage (server persistente para la integración de notebooks de IDEA)";
      After = [ "graphical-session.target" ];
    };
    Service = {
      # PYTHONPATH -- necesario para que el debugger de notebooks de IDEA
      # funcione contra este server. Diagnosticado en vivo (2026-07-28):
      # "ModuleNotFoundError: No module named 'pycharm_jupyter'" (y después,
      # ya con ese arreglado, lo mismo con 'pydev_jupyter_utils') al intentar
      # debuggear. Son helpers propios de la IDE (no están en pip ni en
      # nixpkgs) repartidos en varias subcarpetas de
      # ~/.local/share/JetBrains/IntelliJIdea2026.2/python-ce/helpers/ --
      # pycharm_jupyter vive directo ahí, pydev_jupyter_utils en
      # helpers/jupyter_debug/ (que a su vez importa cosas de helpers/pydev/,
      # el pydevd real). La IDE normalmente inyecta todo esto vía PYTHONPATH
      # cuando ELLA misma lanza el kernel ("Managed"), pero acá usamos
      # "Running Local Server" (server externo, no lanzado por la IDE --
      # justamente para esquivar el bug de websocket del modo Managed, ver
      # más arriba), así que nunca tiene la oportunidad de inyectarlo. Hay
      # que actualizar estas rutas a mano si cambia la versión de IntelliJ
      # IDEA (2026.2 ahora).
      Environment = "PYTHONPATH=%h/.local/share/JetBrains/IntelliJIdea2026.2/python-ce/helpers:%h/.local/share/JetBrains/IntelliJIdea2026.2/python-ce/helpers/pydev:%h/.local/share/JetBrains/IntelliJIdea2026.2/python-ce/helpers/jupyter_debug";
      ExecStart = "${sageWithDebug}/bin/sage --notebook=jupyterlab --no-browser --ip=127.0.0.1 --notebook-dir=%h/IdeaProjects/Jupyter_Notebooks --IdentityProvider.token=818b9fb9de7e0868bf296469e17e3e5549d7725ea6ad2958";
      Restart = "on-failure";
      RestartSec = "5s";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  # --- Neovim/LazyVim: notebooks de Sage vía molten-nvim + chat con Claude
  # Code vía ACP (agentic.nvim) ---
  # lazyvim-nix (pfassina/lazyvim-nix, ver flake.nix) en vez de nixificar
  # LazyVim entero: la config (autocmds/keymaps/options/specs de plugin)
  # queda declarada acá, pero lazy.nvim (el package manager propio de
  # LazyVim) sigue instalando/actualizando los plugins solo -- es el
  # híbrido que recomienda la comunidad en vez de pelear con las
  # actualizaciones de cada plugin individual vía Nix.
  programs.lazyvim = {
    enable = true;
    extraPackages = with pkgs; [
      imagemagick # requerido por molten-nvim/image.nvim para renderizar imágenes
      claude-agent-acp # adaptador ACP oficial -- agentic.nvim lo invoca por PATH.
        # Ya viene wrappeado contra el `claude-code` que ya tenías instalado
        # (ver postInstall del propio paquete en nixpkgs) -- mismo login,
        # sin credenciales nuevas que configurar.
      gcc # image.nvim intenta instalar su propio binding `magick` de Lua vía
        # hererocks (compila un Lua 5.1 propio desde cero) la primera vez
        # que arranca -- confirmado en vivo: fallaba con "couldn't run gcc
        # ...: is gcc in PATH?" porque no había ningún compilador C en el
        # PATH de Neovim. Con gcc disponible, hererocks compila bien y no
        # hace falta pelear por deshabilitar rocks.hererocks (que ni
        # siquiera es una opción que lazyvim-nix exponga -- es del
        # `lazy.setup()` global, no del spec por-plugin). El intento de
        # hererocks queda igual como ruido cosmético en el log de arranque
        # -- confirmado en vivo que `require("magick")` ya funciona bien
        # con el `magick` que se instala vía extraLuaPackages más abajo,
        # sin depender para nada de que hererocks termine de compilar.
      python3Packages.jupytext # CLI que usa jupytext.nvim (plugin más abajo)
        # para convertir .ipynb <-> representación de texto plano con
        # celdas -- sin este binario en PATH, jupytext.nvim solo muestra
        # el JSON crudo del notebook en vez de celdas editables.
    ];

    plugins = {
      molten = ''
        return {
          "benlubas/molten-nvim",
          version = "^1.0.0",
          build = ":UpdateRemotePlugins",
          dependencies = { "3rd/image.nvim" },
          init = function()
            vim.g.molten_image_provider = "image.nvim"
            vim.g.molten_auto_open_output = false
            vim.g.molten_wrap_output = true
            vim.g.molten_virt_text_output = true
          end,
        }
      '';

      # Backend "kitty" -- kitty (ya es la terminal por default, ver
      # modules/desktop.nix) soporta el protocolo de gráficos de kitty
      # nativamente, sin necesitar ueberzugpp de por medio.
      image-nvim = ''
        return {
          "3rd/image.nvim",
          opts = {
            backend = "kitty",
            max_width = 100,
            max_height = 12,
            max_height_window_percentage = math.huge,
            max_width_window_percentage = math.huge,
            window_overlap_clear_enabled = true,
          },
        }
      '';

      # jupytext.nvim -- abre un .ipynb directo como su representación de
      # texto plano (celdas marcadas con # %%, estilo "hydrogen"), para
      # poder editarlo/evaluarlo con molten como si fuera un notebook de
      # verdad, en vez de solo evaluar rangos sueltos de un .py/.sage.
      # lazy = false: recomendado por el propio plugin, para no perderse
      # el autocmd de conversión si el .ipynb es el primer archivo que
      # abrís al arrancar Neovim.
      #
      # custom_language_formatting.sage -- SIN esto, abrir un notebook con
      # kernel "sagemath" crasheaba: el plugin trae una tabla fija de
      # lenguajes (python/julia/r/bash, ver lua/jupytext/utils.lua en su
      # repo) y "sage" no está ahí, así que la extensión de salida quedaba
      # nil y explotaba con "attempt to concatenate local 'extension' (a
      # nil value)". Confirmado leyendo el código fuente real (init.lua):
      # custom_language_formatting SÍ evita esa tabla rota por completo --
      # sale por una rama de código distinta que no la toca.
      # extension = "py" (no "sage") a propósito: ese valor se lo pasa tal
      # cual al comando `jupytext --to <extension>:<style>` real (el CLI
      # de Python, que no tiene idea de qué es "sage") -- "py" con estilo
      # "hydrogen" alcanza para el round-trip .ipynb <-> texto plano.
      # force_ft = "python" solo cambia el resaltado de sintaxis en
      # Neovim, no afecta la conversión en sí.
      jupytext = ''
        return {
          "GCBallesteros/jupytext.nvim",
          opts = {
            style = "hydrogen",
            custom_language_formatting = {
              sage = {
                extension = "py",
                style = "hydrogen",
                force_ft = "python",
              },
            },
          },
          lazy = false,
        }
      '';

      # agentic.nvim -- interfaz de chat con agentes ACP dentro de Neovim.
      # provider = "claude-agent-acp" usa el binario de nixpkgs de arriba;
      # reusa el login de `claude` ya existente, sin API key nueva.
      agentic = ''
        return {
          "carlos-algms/agentic.nvim",
          opts = {
            provider = "claude-agent-acp",
          },
        }
      '';
    };

    config.keymaps = ''
      -- Molten (kernel de Sage) -- ver `:help molten-nvim` para el resto de comandos
      vim.keymap.set("n", "<leader>mi", ":MoltenInit sagemath<CR>", { desc = "Molten: iniciar kernel de Sage" })
      vim.keymap.set("n", "<leader>me", ":MoltenEvaluateOperator<CR>", { desc = "Molten: evaluate operator" })
      vim.keymap.set("n", "<leader>mc", ":MoltenReevaluateCell<CR>", { desc = "Molten: re-evaluar celda" })
      vim.keymap.set("v", "<leader>mv", ":<C-u>MoltenEvaluateVisual<CR>gv", { desc = "Molten: evaluar selección" })
    '';
  };

  # pynvim/jupyter-client/etc -- requeridos por molten-nvim para hablar con
  # el kernel de Jupyter. magick (Lua, no confundir con el imagemagick de
  # arriba) -- lo usa image.nvim para decodificar imágenes.
  programs.neovim = {
    extraPython3Packages = ps: with ps; [ pynvim jupyter-client cairosvg pnglatex plotly pyperclip ];
    extraLuaPackages = ps: [ ps.magick ];
  };

  home.sessionVariables = {
    # JUPYTER_PATH global -- así molten-nvim (que corre bajo el Python de
    # Neovim, no el de Sage) también descubre el kernelspec "sagemath" (ver
    # el `let` de arriba, sageJupyterPath). No rompe nada más: es puramente
    # aditivo (un directorio más donde buscar kernelspecs), y bound a
    # 127.0.0.1 el server real (services.sage-jupyterlab) igual, esta
    # variable ni siquiera lo lanza, solo hace visible su definición.
    JUPYTER_PATH = sageJupyterPath;

    # image.nvim intenta compilar su propio Lua 5.1 vía hererocks al
    # arrancar (para el binding `magick`) -- confirmado en vivo que fallaba
    # primero con "readline/readline.h: No existe el fichero o el
    # directorio" al compilar lua.c (Lua se compila con
    # -DLUA_USE_READLINE), y después -- ya con el header resuelto -- con
    # "no se puede encontrar -lncurses" al LINKEAR (readline en sí depende
    # de ncurses/termcap). Tener los paquetes en el PATH (via gcc, arriba)
    # no alcanza -- el compilador/linker necesitan que sus include/lib
    # queden expuestos explícitamente. CPATH y LIBRARY_PATH son variables
    # estándar que gcc/ld respetan directo, sin necesitar que estos
    # paquetes sean buildInputs de una derivación real. Verificado en vivo
    # compilando Y linkeando lua+luac completos a mano con estas mismas
    # variables antes de aplicar esto.
    CPATH = "${pkgs.readline.dev}/include";
    LIBRARY_PATH = "${pkgs.readline}/lib:${pkgs.ncurses}/lib";
  };
}
