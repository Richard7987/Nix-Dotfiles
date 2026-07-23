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
  services.pipewire.wireplumber.extraConfig."51-bluez-avrcp" = {
    "monitor.bluez.properties" = {
      "bluez5.dummy-avrcp-player" = true;
      "bluez5.codecs" = [ "sbc" "aac" ];
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
    nautilus       # gestor de archivos GTK4 -- hereda el theme de Noctalia solo
                   # (template built-in "gtk4"), sin necesidad de config aparte
    yazi           # gestor de archivos TUI -- único con template oficial de
                   # color de Noctalia (community_ids en home.nix)
    python3        # requerido por el template "kcolorscheme" de Noctalia
                   # (assets/templates/kde/apply.py escribe ~/.config/kdeglobals
                   # para que Kleopatra herede el color) -- sin esto el script
                   # falla en silencio y Kleopatra se queda con el tema por defecto.
    kdePackages.breeze              # estilo Qt que renderiza la paleta de KDE
    kdePackages.plasma-integration  # plugin de QPA platform theme (KDEPlasmaPlatformTheme6.so)
                                    # que aplica kdeglobals a cualquier app Qt -- sin esto
                                    # kdeglobals ya tenía los colores de Noctalia correctos
                                    # (confirmado con un cat real) pero nada los usaba: ni
                                    # Kleopatra ni pinentry-qt (el diálogo de PIN de la
                                    # YubiKey) los mostraban.
    inputs.psysonic.packages.${pkgs.stdenv.hostPlatform.system}.default
      # cliente de música self-hosted (Navidrome), reemplaza a feishin --
      # empaquetado vía su propio flake.nix (no está en nixpkgs). Hace
      # falta apuntarlo a un servidor la primera vez que se abre.
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
           # ya instalado), así que hereda el theme Gruvbox/Noctalia solo vía
           # el template built-in "gtk4" (igual que Nautilus, ver comentario
           # de arriba) sin declarar nada extra. El propio README de Noctalia
           # no recomienda ningún visor de imágenes en particular (fuera de
           # su alcance, mismo caso que el gestor de archivos) -- elegido por
           # consistencia con el resto del setup GTK4 en vez de alternativas
           # nativas de Wayland (swayimg/imv), que no traen esa integración
           # automática de tema y requerirían configurarla a mano.
  ];

  # Necesario para que QT_QPA_PLATFORMTHEME=kde (de abajo) resuelva al plugin
  # de plasma-integration en vez de caer al tema Qt genérico sin colores.
  environment.sessionVariables.QT_QPA_PLATFORMTHEME = "kde";

  # Sin esto, Nautilus no tiene papelera, ni monta MTP/almacenamiento
  # removible/shares de red -- confirmado que services.gvfs.enable es un
  # mkEnableOption que defaultea a false (nixos/modules/services/desktops/gvfs.nix).
  services.gvfs.enable = true;
}
