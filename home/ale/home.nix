{ config, pkgs, lib, inputs, ... }:

{
  imports = [
    inputs.noctalia.homeModules.default
    inputs.dank-material-shell.homeModules.default
  ];

  home.username = "ale";
  home.homeDirectory = "/home/ale";
  # NUNCA cambies esto tras la primera activación (ver la doc de home-manager
  # sobre home.stateVersion). Ponlo igual al system.stateVersion del host.
  home.stateVersion = "26.05";

  programs.home-manager.enable = true;

  # OpenCode -- instalado vía el script curl oficial (~/.opencode/bin), NO
  # como paquete de nixpkgs: nixpkgs-unstable va atrasado (1.18.4) contra el
  # instalador oficial (1.18.9), y cada versión usa su propia base de datos
  # de sesiones (~/.local/share/opencode/opencode{,-stable}.db) -- son
  # incompatibles entre sí, no comparten sesiones. Confirmado en vivo
  # (2026-07-29): el binario de nixpkgs ni siquiera podía listar sesiones
  # creadas por el instalador curl. Esta línea es lo único que faltaba para
  # que el binario curl aparezca en el PATH de toda sesión (gráfica y
  # terminales nuevas) -- antes solo la terminal donde corrió el instalador
  # lo tenía, porque el script no toca .zshrc/.bashrc/.zprofile.
  home.sessionPath = [ "$HOME/.opencode/bin" ];

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

  # --- niri + DankMaterialShell: migración en curso, conviven con Hyprland+Noctalia ---
  # (ver modules/niri.nix para el detalle completo del scoping). systemd.enable
  # = false acá también, mismo motivo: DMS se lanza vía `spawn-at-startup` en
  # niri.kdl en vez de como servicio systemd mientras las dos sesiones convivan.
  #
  # settings/session sin declarar A PROPÓSITO: el tema queda 100% dinámico
  # (matugen deriva colores de lo que elijas en vivo desde la propia UI de DMS,
  # wallpaper picker incluido) en vez de fijarlo desde Nix -- pedido explícito.
  # Fijar acá `session.wallpaperPath` reafirmaría el mismo wallpaper en cada
  # rebuild y pisaría cualquier cambio hecho desde la UI, el mismo problema que
  # ya pasa con Noctalia (su settings.toml en runtime le gana al config.toml
  # estático de Nix, ver NOTES.md) -- se elige explícitamente NO repetirlo acá.
  # Todo lo que NO es tema (binds, window rules, arranque) sí queda declarado
  # en niri.kdl / modules/niri.nix.
  programs.dank-material-shell = {
    enable = true;
    systemd.enable = false;
  };

  # mkOutOfStoreSymlink en vez de source normal MIENTRAS se afina la config a
  # ojo (niri recarga en caliente al guardar) -- volver a `source = ./niri.kdl`
  # cuando quede estable, para que sea de nuevo un symlink de solo lectura al
  # store como el resto de los xdg.configFile de este repo.
  xdg.configFile."niri/config.kdl".source =
    config.lib.file.mkOutOfStoreSymlink "/nixdots/home/ale/niri.kdl";

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

  # --- ssh: IdentityAgent explícito (bug real de IDEA, 2026-07-28) ---
  # enableSshSupport de arriba exporta SSH_AUTH_SOCK vía .zshenv/.zprofile --
  # alcanza para cualquier terminal real, pero NO para IntelliJ IDEA: su
  # terminal embebida / git4idea arrancan subprocesos con un entorno propio
  # que no hereda esa variable (confirmado en vivo: SSH_AUTH_SOCK ausente
  # ahí aunque el proceso principal de IDEA sí la tenga en /proc/<pid>/environ
  # -- bug documentado de JetBrains, EnvironmentUtil cachea/reconstruye el
  # entorno de los hijos aparte). Probado hasta -Dij.load.shell.env=true en
  # idea64.vmoptions (el fix oficial) y sigue sin aparecer -- IDEA decide
  # saltarse esa recaptura si detecta SHLVL=1 ("launched from a terminal"),
  # que es justo este caso. En vez de pelear con eso: IdentityAgent le dice
  # a `ssh` directamente dónde está el socket del agente, sin depender de
  # que la variable de entorno llegue bien -- soluciona el problema de raíz
  # para CUALQUIER programa (no solo IDEA) que herede mal el entorno gráfico.
  # Ruta hardcodeada (no "$SSH_AUTH_SOCK", que es justo la variable que
  # puede faltar): /run/user/1000/gnupg/S.gpg-agent.ssh es la ruta estable
  # que gpg-agent siempre usa para este usuario (UID 1000), confirmada con
  # `systemctl --user show-environment` y estable entre reinicios del
  # agente (gpg-agent recrea el socket en el mismo path, no lo renombra).
  programs.ssh = {
    enable = true;
    # enableDefaultConfig = false + los valores de abajo copiados a mano:
    # el módulo advierte que esos defaults implícitos se van a deprecar, y
    # da este mismo bloque como reemplazo exacto (ver modules/programs/ssh.nix
    # de home-manager) -- sin cambio de comportamiento, solo lo hace explícito.
    enableDefaultConfig = false;
    # settings, no matchBlocks -- confirmado con build real: matchBlocks (y
    # matchBlocks.*.extraOptions) están deprecados a favor de esto.
    settings."*" = {
      IdentityAgent = "/run/user/1000/gnupg/S.gpg-agent.ssh";
      ForwardAgent = false;
      AddKeysToAgent = "no";
      Compression = false;
      ServerAliveInterval = 0;
      ServerAliveCountMax = 3;
      HashKnownHosts = false;
      UserKnownHostsFile = "~/.ssh/known_hosts";
      ControlMaster = "no";
      ControlPath = "~/.ssh/master-%r@%n:%p";
      ControlPersist = "no";
    };
  };

  # --- delta: diffs con resaltado de sintaxis ---
  # Repos migrados de got a git (2026-07-28, ver NOTES.md) -- a diferencia de
  # got, git SÍ invoca un pager propio (core.pager), así que
  # programs.git.delta.enable = true (más abajo, junto a programs.git) alcanza
  # para que `git diff`/`git log -p`/`git show` salgan coloreados solos, sin
  # necesitar las funciones manuales gotd/gotl de antes (sacadas). El alias
  # `gd` del plugin "git" de oh-my-zsh (`git diff`) ya hereda esto gratis.
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
    # vi/vim -> nvim: sin programs.neovim (ver comentario más abajo sobre
    # por qué no se usa ese módulo), el alias hay que ponerlo a mano.
    shellAliases = {
      vi = "nvim";
      vim = "nvim";
    };
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
      # /nixdots volvió a ser un repo git normal (2026-07-28, ver NOTES.md --
      # antes fue work tree de got, migración documentada como "Migración a
      # got puro" en NOTES.md 2026-07-22). programs.git.signing.signByDefault
      # ya está en true (más arriba), así que este commit de flake.lock queda
      # firmado con la YubiKey solo, sin nada especial acá.
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
          if [ -n "$(git status --porcelain -- flake.lock)" ]; then
            git commit -m "Actualiza flake.lock" -- flake.lock
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

      # herdr YA NO se auto-lanza al abrir kitty (2026-07-28, a pedido del
      # usuario) -- sigue instalado (home.packages) para correrlo a mano
      # (`herdr`) cuando haga falta. $HERDR_ENV/HERDR_PANE_ID/etc. (las
      # variables que herdr exporta dentro de sus propios panes, confirmado
      # con `herdr pane run --session default <pane-id> 'env'`) documentadas
      # acá por si se reactiva el auto-launch más adelante.
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

  # git (a diferencia de got) invoca su propio pager -- programs.delta acá
  # (NO programs.git.delta, renombrado -- confirmado con build real: "has
  # been renamed to `programs.delta.enable'") alcanza para que
  # `git diff`/`git log -p`/`git show` (y el alias `gd` de oh-my-zsh) salgan
  # coloreados con delta solos, sin funciones manuales. enableGitIntegration
  # explícito: el auto-enable basado en programs.git.enable quedó deprecado.
  # ver xdg.configFile."delta/config" más arriba para el styling.
  programs.delta = {
    enable = true;
    enableGitIntegration = true;
  };

  # --- Neovim + LazyVim ---
  # home.packages, NO programs.neovim: ese módulo SIEMPRE gestiona
  # ~/.config/nvim/init.lua como symlink al store (aunque no declares
  # ningún plugin/extraConfig -- confirmado en vivo, 2026-08-02: pisó el
  # init.lua de LazyVim escrito a mano nada más activar, dejando el intro
  # default de Neovim en vez de arrancar lazy.nvim). Un init.lua inmutable
  # en el store es incompatible con LazyVim, que necesita reescribir
  # lazy-lock.json en cada :Lazy sync. Acá simplemente instalamos el
  # binario + las herramientas que pide LazyVim (:checkhealth lazy) --
  # git ya lo pone programs.git.enable, no hace falta repetirlo. Nada de
  # PATH "wrappeado": nvim corre desde la shell interactiva normal (zsh),
  # que ya hereda el PATH completo del profile de home-manager -- el bug
  # clásico de NixOS (wrapper con --set PATH en vez de --prefix) solo
  # aplica cuando el propio derivation de neovim wrappea el binario, cosa
  # que no hacemos acá.
  #
  # ripgrep/fd: los invoca directo LazyVim (snacks.nvim/fzf-lua) como
  # binarios de shell. lazygit: keymap nativo de LazyVim (<leader>gg).
  # unzip: Mason (gestor de LSPs/linters de LazyVim, corre en runtime) lo
  # necesita para descomprimir descargas. gcc/gnumake: fallback nativo de
  # blink.cmp si no logra bajar su binario prebuilt para esta plataforma.
  #
  # La config de LazyVim en sí (~/.config/nvim) queda FUERA de este repo a
  # propósito, mismo criterio que TeXstudio más abajo: lazy.nvim reescribe
  # lazy-lock.json en cada actualización de plugin. ~/.config/nvim/lua/
  # plugins/base16.lua + lua/matugen.lua sincronizan el colorscheme de
  # Neovim con el tema Gruvbox de Noctalia (programs.noctalia.settings.theme
  # más arriba).
  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
  };

  # --- Molten (celdas Jupyter dentro de Neovim): entorno Python dedicado ---
  # NixOS no tiene un "python del sistema" al que agregarle paquetes con pip
  # (todo se declara) -- esto reutiliza el mismo intérprete python3 de
  # nixpkgs que ya usa el resto del sistema, sumándole solo lo que pide
  # Molten/jupytext: pynvim + jupyter-client (host del kernel), ipykernel
  # (kernel de Python en sí), cairosvg + pillow (Molten renderiza vía
  # image.nvim -- ver lua/plugins/image.lua -- pero cairosvg/pillow cubren
  # salidas SVG/PIL que ese pipeline no toca directo), jupytext (CLI que usa
  # jupytext.nvim para convertir .ipynb en el momento).
  #
  # home.file (no home.packages): NO va al PATH general a propósito -- si
  # "python3" quedara en el PATH de toda la shell, pisaría cualquier otro
  # python3 que otra herramienta del sistema espere encontrar ahí. En vez de
  # eso, symlink de nombre ESTABLE (~/.local/share/nvim-python3) que
  # solo lua/config/options.lua referencia (vim.g.python3_host_prog) y que
  # lua/config/lazy.lua antepone al $PATH interno de Neovim nada más --
  # el symlink en sí no cambia de ruta aunque el store path de adentro
  # cambie en cada rebuild, así que ninguna referencia se rompe.
  home.file.".local/share/nvim-python3".source =
    pkgs.python3.withPackages (ps: with ps; [
      pynvim
      jupyter-client
      ipykernel
      cairosvg
      pillow
      jupytext
      pylatexenc # da el CLI `latex2text` -- uno de los dos conversores que
        # render-markdown.nvim prueba en orden (utftex, latex2text; ver
        # settings.lua del plugin) para volver fórmulas LaTeX en unicode
        # inline. utftex no está en nixpkgs, pero con latex2text solo alcanza
        # (el converter list prueba en orden hasta el primero que exista).
    ]);

  # Los LSPs/formatters/linters que reemplazan a Mason (ver
  # lua/plugins/mason-disable.lua) van en home.packages, más abajo -- una
  # sola lista, dos `home.packages` separados chocan (ver el comentario ahí).

  # --- TeXstudio: conecta Tectonic como compilador por defecto ---
  # TeXstudio no tiene una opción declarativa de home-manager (no existe
  # `programs.texstudio`) y su config (~/.config/texstudio/texstudio.ini)
  # NO puede manejarse vía xdg.configFile: a diferencia de delta/herdr de
  # abajo, TeXstudio reescribe ese archivo en cada uso (ventana, sesión,
  # historial de archivos recientes) -- si xdg.configFile lo convirtiera en
  # symlink al store (inmutable), esas escrituras fallarían en silencio.
  # En vez de eso, activation script idempotente: solo siembra la clave la
  # primera vez (si "Tools\Commands\tectonic" ya está seteada, no la toca),
  # así que un cambio posterior del compilador por defecto hecho a mano
  # desde la UI de TeXstudio se respeta en rebuilds futuros.
  #
  # Formato de la clave confirmado en vivo (2026-07-28): TeXstudio guarda
  # TODO bajo una única sección [texmaker] (nombre heredado de Texmaker, su
  # predecesor), con las claves anidadas unidas por "\" en vez de blocks
  # anidados reales -- confirmado contra un texstudio.ini real de un
  # usuario (thatlittleboy/TeXstudio-Qt-Stylesheet en GitHub) y verificado
  # relanzando TeXstudio de verdad contra este archivo: lo reescribió en su
  # propio formato canónico (sin comillas), prueba de que lo parseó y
  # adoptó como compilador activo, no que simplemente no falló al leerlo.
  # "compile=txs:///<id>" es el mecanismo genérico de TeXstudio para elegir
  # QUÉ comando ejecuta el botón de compilar -- <id> puede ser cualquier
  # comando registrado, incluido uno custom como "tectonic" acá, no solo
  # los que trae por default (pdflatex/xelatex/lualatex/latexmk).
  # --synctex en el comando de tectonic para que el forward/inverse search
  # del visor de PDF integrado de TeXstudio (click en el PDF -> salta al
  # .tex) siga funcionando igual que con pdflatex.
  home.activation.texstudioTectonicCompiler = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    CONFIG_FILE="$HOME/.config/texstudio/texstudio.ini"
    $DRY_RUN_CMD mkdir -p "$(dirname "$CONFIG_FILE")"
    if [ ! -f "$CONFIG_FILE" ]; then
      $DRY_RUN_CMD printf '[texmaker]\n' > "$CONFIG_FILE"
    fi
    if ! grep -q '^Tools\\Commands\\tectonic=' "$CONFIG_FILE" 2>/dev/null; then
      $DRY_RUN_CMD sed -i '/^\[texmaker\]/a Tools\\Commands\\tectonic="tectonic --synctex %.tex"\nTools\\Commands\\compile=txs:///tectonic' "$CONFIG_FILE"
    fi
  '';

  # --- LibrePods (control de AirPods) ---
  # Ya no depende de bajar el AppImage nightly a mano -- se compila de fuente
  # (ver pkgs/librepods.nix para el porqué y las verificaciones hechas).
  # (El fix de AVRCP para play/pause/skip va en modules/desktop.nix, vía
  # services.pipewire.wireplumber.extraConfig -- no aquí. Ver el comentario
  # ahí para el porqué.)

  home.packages = with pkgs; [
    neovim # editor -- ver comentario "Neovim + LazyVim" más arriba sobre por
      # qué es home.packages y no programs.neovim
    ripgrep # invocado por snacks.nvim/fzf-lua dentro de LazyVim
    fd # ídem, para find de archivos
    lazygit # invocado por el keymap nativo <leader>gg de LazyVim
    unzip # usado por varios plugins de nvim al descomprimir descargas (ej. releases de GitHub)
    gcc # fallback nativo de blink.cmp si no baja su binario prebuilt
    gnumake # ídem

    # --- LSPs/formatters/linters de los extras de LazyVim (ver lazyvim.json) ---
    # Mason (el instalador default de LazyVim) no funciona en NixOS: no
    # puede correr binarios bajados de internet (store inmutable, sin
    # linker FHS estándar) -- confirmado en vivo, 2026-08-02: nil_ls/gopls
    # fallaron por falta de cargo/go (Mason los compila, no baja prebuilt) y
    # marksman SÍ bajó un binario prebuilt pero crasheó con SIGABRT al
    # ejecutarlo. lua/plugins/mason-disable.lua apaga mason.nvim/
    # mason-lspconfig/mason-tool-installer del todo; esta lista es el
    # reemplazo 1:1 de cada herramienta que Mason intentaba instalar,
    # agrupada por extra.
    nil # lang.nix
    go gopls gofumpt golangci-lint gotools # lang.go (gotools da `goimports`)
    jdt-language-server # lang.java (nvim-jdtls) -- ya trae su propio JRE
    kotlin-language-server ktlint # lang.kotlin
    dockerfile-language-server docker-compose-language-service hadolint # lang.docker
      # -- el binario real de dockerfile-language-server-nodejs se llama
      # `docker-langserver` (el nombre del paquete no es el del binario),
      # que es justo el nombre que nvim-lspconfig ya busca por defecto
    neocmakelsp cmake-format # lang.cmake (cmake-format da también `cmake-lint`)
    vscode-langservers-extracted # lang.json -- da `vscode-json-language-server` (jsonls)
    astro-language-server vtsls # lang.astro (vtsls: LSP de TS/JS que usa como
      # base; el binario real de astro-language-server se llama `astro-ls`,
      # que es el nombre que nvim-lspconfig ya busca por defecto)
    marksman markdownlint-cli2 markdown-toc # lang.markdown
    pyright ruff # lang.python -- Mason los bajó bien (binarios simples, sin
      # deps nativas raras), pero se migran igual por consistencia
    tree-sitter # tree-sitter-cli, usado por varios parsers custom
    stylua # formatter de Lua -- para esta misma config de nvim
    shfmt # formatter de shell scripts
    # lang.julia (julials) queda afuera de esta lista: no es un binario
    # descargado, nvim-lspconfig arranca `julia` directo con un snippet que
    # hace `using LanguageServer, SymbolServer` -- esos dos paquetes se
    # agregan al entorno de Julia del usuario (~/.julia) con `julia -e
    # 'using Pkg; Pkg.add(...)'`, igual que IJulia.

    imagemagick # backend magick_cli de image.nvim (lua/plugins/image.lua) --
      # shellea al binario `magick` en vez de compilar el rock FFI vía
      # luarocks/hererocks, que fue justo lo que dejó a medias el intento
      # previo de este mismo setup (ver ~/.config/nvim.bak-20260802-174115/
      # lazy-lock.json: tenía "hererocks" suelto, sin ningún plugin que lo
      # declarara -- nunca llegó a terminarse).
    delta # diffs con resaltado (git diff/log/show vía programs.git.delta.enable) -- ver xdg.configFile."delta/config" más arriba
    yubikey-manager
    (callPackage ../../pkgs/librepods.nix { })
    (python3Packages.callPackage ../../pkgs/clamui.nix { }) # GUI de ClamAV -- clamav en sí va en configuration.nix (services.clamav), clamui solo invoca `clamscan` por $PATH
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
    # Tectonic -- motor LaTeX self-contained (bajo el capó usa XeTeX + un
    # subconjunto de TeX Live vendorizado, sin depender de una instalación de
    # TeX Live completa). Va en home.packages (no environment.systemPackages)
    # porque es una herramienta de usuario, no del sistema. useUserPackages =
    # true (ver flake.nix) publica esto en /etc/profiles/per-user/ale/bin,
    # que NixOS agrega al PATH de toda la sesión gráfica (greetd/Hyprland vía
    # PAM), no solo a shells interactivas -- así que cualquier editor
    # lanzado desde el launcher de Noctalia lo hereda sin configuración
    # extra. Probado en un principio con TeXiFy-IDEA (IntelliJ IDEA), pero
    # se abandonó esa ruta (ver NOTES.md) a favor de TeXstudio, más abajo.
    tectonic
    ghostscript # da el binario `gs` -- junto con tectonic de arriba, es el
      # pipeline LaTeX->PNG que usa `slides` (ver modules/desktop.nix) para
      # renderizar fórmulas; sin este paquete tectonic compila el PDF pero
      # falta el paso de rasterizado a PNG.
    julia-bin # ejecución de bloques ```julia con Ctrl+E en `slides` (ver
      # modules/desktop.nix); julia-bin en vez de julia porque en nixpkgs
      # "julia" a secas compila el lenguaje entero desde fuente
      # (USE_BINARYBUILDER=0), mientras que julia-bin sólo empaqueta el
      # tarball prebuilt que publica JuliaLang -- mismo binario final, sin
      # el build larguísimo.
    # TeXstudio -- editor LaTeX dedicado, en vez de IDEA + TeXiFy-IDEA (esa
    # combinación quedó descartada: el "Tectonic SDK" de TeXiFy-IDEA valida
    # el home path buscando una carpeta "urls" adentro, layout viejo del
    # caché de Tectonic que ya no existe en versiones actuales -- ver
    # NOTES.md). Config de compilador -> Tectonic vía home.activation
    # (texstudioTectonicCompiler, más arriba), no a mano en la UI.
    texstudio
    # TeX Live completo (todo CTAN) -- segundo compilador disponible
    # además de Tectonic, para documentos que necesiten
    # pdflatex/xelatex/lualatex o un paquete que Tectonic todavía no trae
    # vendorizado. TeXstudio detecta ambos solo (busca pdflatex/xelatex/etc
    # en PATH para el combo "Default Compiler"); no hace falta wiring extra
    # más allá de tenerlo instalado. texliveFull, no texlive.combined.scheme-full
    # (deprecado, se va en Nixpkgs 27.05) -- mismo contenido, atributo top-level.
    texliveFull
    zed-editor # editor -- paquete directo de nixpkgs (el binario se llama
      # `zeditor`, no `zed`; el .desktop instalado sí queda como "Zed" en el
      # launcher)
  ];
}
