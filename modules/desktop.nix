{ config, lib, pkgs, inputs, ... }:

{
  # pkexec necesita el wrapper setuid de NixOS para funcionar (el binario
  # crudo del store no tiene setuid). Sin esto, el propio módulo de gamemode
  # (modules/graphics.nix) apunta su servicio systemd a
  # "${security.wrapperDir}/pkexec", que no existiría -> las operaciones
  # privilegiadas de gamemode (cpugovctl/gpuclockctl) fallarían.
  security.polkit.enablePkexecWrapper = true;

  networking.networkmanager.enable = true; # applet de red de DMS habla con NetworkManager por D-Bus
  hardware.bluetooth.enable = true;

  # El control de Xbox Wireless Controller (045e:0b13, firmware 5.09) empareja
  # por Bluetooth LE puro (HID-over-GATT, servicio 0x1812) -- confirmado en
  # vivo (2026-07-26): `bluetoothctl` lo lista solo como "LE", sin "BREDR".
  # Sin lo de abajo, el pairing/bonding se completa bien (`Paired: yes`,
  # `Bonded: yes` en bluetoothctl) pero el propio control corta la conexión
  # segundos después (`org.bluez.Reason.Remote, Connection terminated by
  # remote user` en btmon) -- por eso queda parpadeando en loop. Mismo
  # síntoma y mismo fix reportados en NixOS Discourse
  # (discourse.nixos.org/t/xbox-controller-stuck-in-a-disconnect-reconnect-loop/67845):
  # `Privacy = "device"` corrige el manejo de direcciones LE privadas
  # (el punto que más importa acá, dado que este control es LE-only) y
  # `JustWorksRepairing = "always"` evita que un bond a medio formar de un
  # intento previo bloquee el re-pairing. `Class`/`FastConnectable` los deja
  # el mismo hilo pero son para BR/EDR clásico -- no afectan a este control,
  # se agregan solo por paridad con el fix confirmado.
  hardware.bluetooth.settings = {
    General = {
      Privacy = "device";
      JustWorksRepairing = "always";
      Class = "0x000100";
      FastConnectable = "true";
    };
  };

  services.power-profiles-daemon.enable = true;
  services.upower.enable = true;

  # LibrePods usa org.bluez.AdvertisementMonitorManager1.RegisterMonitor para
  # su "LE monitor" (detecta el AirPods por advertisements BLE cuando no está
  # conectado por Bluetooth clásico) -- esa interfaz D-Bus es experimental en
  # BlueZ (confirmado en `bluetoothd --help`: "-E, --experimental  Enable
  # experimental D-Bus interfaces") y no viene activada por default en el
  # módulo de NixOS. Sin esto: "Method RegisterMonitor ... doesn't exist".
  systemd.services.bluetooth.serviceConfig.ExecStart = [
    ""
    "${config.hardware.bluetooth.package}/libexec/bluetooth/bluetoothd -E -f /etc/bluetooth/main.conf"
  ];

  # El adaptador Bluetooth de esta máquina (Intel AC9560, combo con el WiFi)
  # cuelga del bus USB interno (confirmado: `/sys/bus/usb/devices/1-14/`,
  # idVendor 8087:0aaa) con autosuspend USB activado por default
  # (`power/control: auto`, `power/autosuspend_delay_ms: 2000` -- confirmado
  # leyendo el sysfs real de esta laptop). Diagnosticado en vivo (2026-07-26):
  # el audio de los AirPods se corta a los pocos minutos de uso incluso con
  # `bluez5.codecs` ya restringido a sbc/aac (ver más arriba) y sin xruns ni
  # errores reportados por PipeWire (`pw-top` con `ERR: 0` durante el corte)
  # -- consistente con el bus USB suspendiendo el controlador Bluetooth en
  # medio del stream A2DP y no con un problema de códec/negociación. Este es
  # un problema ampliamente documentado para adaptadores Intel combo con
  # `btusb` (ver foros de Arch/Fedora sobre `enable_autosuspend` de btusb).
  # Deshabilitarlo a nivel de módulo del kernel es más robusto que una regla
  # de udev atada al path del bus (que puede cambiar entre reinicios).
  boot.extraModprobeConfig = ''
    options btusb enable_autosuspend=0
  '';

  # --- Audio (pipewire) — necesario para los atajos de volumen (dms ipc audio, en niri.kdl) ---
  security.rtkit.enable = true;
  services.pulseaudio.enable = false; # renombrado desde hardware.pulseaudio (confirmado con nix eval real)
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    wireplumber.enable = true;
  };

  # Sin esto, el clock del grafo de PipeWire queda fijo en 48000 Hz sin
  # margen (default de PipeWire: default.clock.allowed-rates vacío = una
  # sola tasa) -- confirmado en vivo con `pw-metadata -n settings`. Con esto
  # poblado, el grafo puede cambiar de tasa para matchear la nativa de un
  # stream "bit-perfect" (ej. psysonic con álbumes hi-res, "audio stream
  # opened at 192000 Hz (exact)" en sus logs) en vez de forzar resample.
  #
  # NO fue la causa del audio cortado que motivó esto -- esa fue una función
  # de hi-res streaming propia de psysonic (bug/comportamiento de esa app,
  # se resolvió desactivándola ahí). Este cambio queda solo porque sigue
  # siendo una mejora real y correcta para el DAC hi-res (HiBy FC4) más allá
  # de ese diagnóstico puntual.
  services.pipewire.extraConfig.pipewire."92-clock-rates" = {
    "context.properties" = {
      "default.clock.rate" = 48000;
      "default.clock.allowed-rates" = [ 44100 48000 88200 96000 176400 192000 ];
    };
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
  # bluez5.codecs restringido -- diagnosticado en vivo en esta máquina: el
  # códec que negociaba por defecto (sbc_xq, mayor bitrate) producía audio
  # cortado en los AirPods con el adaptador Bluetooth de esta laptop (Intel
  # AC9560). Confirmado con una prueba de control (mismos AirPods sonando
  # perfecto en el celular) que no era ni el hardware de los AirPods ni el
  # entorno. Propiedad real confirmada contra la doc de PipeWire
  # (pipewire-props(7): "bluez5.codecs # JSON array of string -- Enabled
  # A2DP codecs (default: all)"). Restringir acá (nivel de sistema) es más
  # robusto que parchear LibrePods -- ninguna app puede pedir un códec que
  # ni siquiera se ofrece en la negociación.
  # "aac" agregado temporalmente (2026-07-13) para comparar contra "sbc":
  # sbc sonó bien al principio pero se degradó tras un rato de uso -- puede
  # ser que ninguno de los dos aguante sostenido en este adaptador. Si tras
  # probar aac un buen rato tampoco aguanta, hay que investigar otra causa
  # (térmica/firmware) en vez de seguir cambiando códecs.
  #
  # "sbc" sacado de la lista (2026-08-10): forzando aac a mano andaba bien,
  # pero al reproducir música con pysonic PipeWire renegociaba a sbc de
  # nuevo. `bluez5.codecs` no es una preferencia, es la lista de códecs
  # ofrecidos en la negociación -- sacando "sbc" del todo, PipeWire no
  # puede caer a él sin importar qué pida la app.
  services.pipewire.wireplumber.extraConfig."51-bluez-avrcp" = {
    "monitor.bluez.properties" = {
      "bluez5.dummy-avrcp-player" = true;
      "bluez5.codecs" = [ "aac" ];
    };
  };

  # gnome-keyring implementa el Secret Service (org.freedesktop.secrets) que
  # tanto DankCalendar (dcal, credenciales CalDAV -- ver core/cmd/dcal/
  # keyring_migrate.go del propio proyecto) como Chromium Safe Storage
  # necesitan por D-Bus. programs.niri.enable (modules/niri.nix) ya deja esto
  # en `lib.mkDefault true` -- se declara acá explícito de todas formas
  # porque el módulo de greetd (nixos/modules/services/display-managers/
  # greetd.nix) conecta `security.pam.services.greetd.enableGnomeKeyring` a
  # este mismo booleano por default, y así queda documentado en un solo
  # lugar el motivo real (auto-unlock del keyring con el password de login,
  # sin tocar PAM a mano).
  services.gnome.gnome-keyring.enable = true;

  # --- DankMaterialShell Greeter ---
  # package/quickshell.package pineados EXPLÍCITAMENTE al paquete del flake
  # de DMS (inputs.dank-material-shell, ver flake.nix) -- el default del
  # módulo cae a `programs.dms-shell` (el paquete de NIXPKGS, no usado en
  # este repo, ver modules/niri.nix) si no se fija así, lo que produciría
  # skew de versión entre el DMS real (sesión) y el que corre en el greeter.
  # configHome: copia settings.json/session.json/dms-colors.json del usuario
  # al greeter -- mismo wallpaper/tema (matugen) que en la sesión real, en
  # vez de la UI default sin personalizar.
  services.displayManager.dms-greeter = {
    enable = true;
    package = config.programs.dank-material-shell.package;
    quickshell.package = config.programs.dank-material-shell.quickshell.package;
    compositor.name = "niri";
    configHome = "/home/ale";
  };

  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    noto-fonts
    noto-fonts-color-emoji # renombrado desde noto-fonts-emoji (confirmado con nix eval real: el nombre viejo tira error duro)
  ];

  environment.systemPackages = with pkgs; [
    kdePackages.kleopatra
    inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.default
    kitty          # terminal (Mod+Return en niri.kdl)
    brightnessctl  # atajos de brillo (XF86MonBrightness* en niri.kdl, vía dms ipc brightness)
    nautilus       # gestor de archivos GTK4 -- hereda el theme (matugen) de DMS solo
                   # (escribe gtk-4.0/gtk.css directo, confirmado en core/internal/
                   # matugen/matugen.go), sin necesidad de config aparte
    yazi           # gestor de archivos TUI. DMS no trae template propio para yazi
                   # (a diferencia de Noctalia, que sí lo tenía vía community_ids) --
                   # queda sin tema Gruvbox automático hasta que exista un template.
    kdePackages.breeze              # estilo Qt que renderiza la paleta de KDE
    kdePackages.plasma-integration  # plugin de QPA platform theme (KDEPlasmaPlatformTheme6.so)
                                    # que aplica kdeglobals a cualquier app Qt -- sin esto
                                    # Kleopatra y pinentry-qt (el diálogo de PIN de la
                                    # YubiKey) no muestran los colores aunque kdeglobals
                                    # ya los tenga. DMS también escribe su propio template
                                    # kcolorscheme (matugen/configs/kcolorscheme.toml del
                                    # flake) -- sin python de por medio (a diferencia de
                                    # Noctalia) -- pero solo lo APLICA si ya elegiste
                                    # "DankMatugen" como color scheme de KDE una vez (ver
                                    # matugen.go:isDMSKDEColorSchemeActive); hacelo desde
                                    # Configuración del sistema o `dms ipc theme apply` si
                                    # Kleopatra/pinentry no toman el color.
    inputs.psysonic.packages.${pkgs.stdenv.hostPlatform.system}.default
      # cliente de música self-hosted (Navidrome), reemplaza a feishin --
      # empaquetado vía su propio flake.nix (no está en nixpkgs). Hace
      # falta apuntarlo a un servidor la primera vez que se abre.
    inputs.nezzontli-ctl.packages.${pkgs.stdenv.hostPlatform.system}.default
      # TUI para crear/editar contenido de nezzontli.xyz sin CMS externo --
      # comando "ctl". Por default apunta a ~/projects/website; se puede
      # cambiar con NEZZONTLI_REPO_PATH o desde su propia pantalla de
      # Configuración.
    inputs.slides.packages.${pkgs.stdenv.hostPlatform.system}.default
      # Presentador de terminal (comando "slides"), fork personal con
      # LaTeX/imágenes/bibliografía/reveal/ejecución de código -- ver
      # ~/projects/slides. Necesita tectonic y ghostscript en PATH para
      # renderizar fórmulas, y julia-bin para el Ctrl+E de bloques
      # ```julia; los tres están en home.nix (paquetes de usuario, no del
      # sistema), o vía el devShell del propio repo.
    got  # VCS de este mismo repo (/nixdots ya es un work tree de got, sin
         # .git -- ver "Migración a got puro" en NOTES.md, 2026-07-22).
         # Reusa ssh-agent para clone/fetch/send por ssh://, igual que git.
         # "got commit" NO soporta firma GPG ni SSH (solo "got tag -S" firma,
         # y solo con SSH) -- los commits de este repo quedan sin firmar
         # desde la migración. El autor de los commits está declarado en
         # got.conf del repo bare (~/nixdots.git/got.conf), NO se resuelve
         # de programs.git/~/.gitconfig -- got solo lee el ~/.gitconfig
         # clásico como último recurso, y este sistema usa el config de git
         # en formato XDG (~/.config/git/config, ver home.nix), que got no
         # mira. programs.git sigue instalado a nivel de sistema solo por
         # otros repos ajenos a /nixdots.

    mpv  # reproductor de video/audio. Verificado con `nix eval`/`nix build`
         # contra el nixpkgs real (no de memoria) que el `pkgs.mpv` de acá ya
         # trae todo lo necesario para "cualquier tipo de video" sin agregar
         # nada más: enlaza `pkgs.ffmpeg` (variante "small", que pese al
         # nombre incluye withHeadlessDeps=true -- confirmado en
         # ffmpeg/generic.nix) con dav1d (AV1), libaom, libvpx (VP8/VP9),
         # x264/x265, libbluray, y sobre todo `nv-codec-headers` --
         # confirmado en buildInputs -- que habilita nvdec/nvenc (decode por
         # hardware en la Nvidia real de esta laptop vía `--hwdec=nvdec`, sin
         # depender del shim vaapi-nvidia que no está instalado). El wrapper
         # `pkgs.mpv` (no mpv-unwrapped) además arrastra `yt-dlp` solo, así
         # que reproducir una URL también funciona sin instalar nada aparte.
         # No hizo falta pasar a `ffmpeg-full`: agrega casi todo encoders/
         # filtros raros irrelevantes para reproducir, no decoders extra.

    loupe  # visor de imágenes -- GTK4/libadwaita (mismo stack que Nautilus,
           # ya instalado), así que hereda el theme (matugen/DMS) solo, sin
           # declarar nada extra -- elegido por consistencia con el resto del
           # setup GTK4 en vez de alternativas nativas de Wayland (swayimg/
           # imv), que no traen esa integración automática de tema y
           # requerirían configurarla a mano.
  ];

  # Necesario para que QT_QPA_PLATFORMTHEME=kde (de abajo) resuelva al plugin
  # de plasma-integration en vez de caer al tema Qt genérico sin colores.
  environment.sessionVariables.QT_QPA_PLATFORMTHEME = "kde";

  # XLOCALEDIR: sin esto, libxkbcommon busca los archivos Compose (dead
  # keys/secuencias de teclado, ej. lo que usa altgr-intl en niri.kdl) en el
  # path FHS clásico "/usr/share/X11/locale", que en NixOS no existe --
  # xkb_compose_table_new_from_locale() falla la búsqueda para es_MX.UTF-8 y
  # cualquier app que no maneje ese error a propósito se cae. Diagnosticado
  # en vivo (2026-08-10): LibrePods (usa winit para su ventana/tray) crasheaba
  # con SIGABRT en el arranque (panic en winit::...::xkb::Context::new,
  # backtrace real vía `coredumpctl info`) hasta que reintentaba lo
  # suficiente como para que la condición de carrera no se diera. Confirmado
  # el fix en vivo corriendo el binario a mano con esta variable puesta --
  # deja de crashear. Se pone acá (global) y no solo en el servicio de
  # LibrePods porque cualquier otra app Rust/GTK que use libxkbcommon para
  # compose puede pegar contra el mismo gap.
  environment.sessionVariables.XLOCALEDIR = "${pkgs.libx11}/share/X11/locale";

  # Sin esto, Nautilus no tiene papelera, ni monta MTP/almacenamiento
  # removible/shares de red -- confirmado que services.gvfs.enable es un
  # mkEnableOption que defaultea a false (nixos/modules/services/desktops/gvfs.nix).
  services.gvfs.enable = true;
}
