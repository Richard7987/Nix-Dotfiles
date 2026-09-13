{ config, lib, pkgs, ... }:

{
  # --- niri ---
  # Única sesión del sistema desde la Fase 3 de la migración (ver NOTES.md) --
  # Hyprland+Noctalia ya no existen en este repo. El módulo de nixpkgs
  # (nixos/modules/programs/wayland/niri.nix) ya deja instalado el paquete,
  # registra la sesión en el display manager, activa gnome-keyring y arma xdg.portal
  # con xdg-desktop-portal-gnome (default niri/gtk, FileChooser vía Nautilus, Secret
  # vía gnome-keyring) -- no hace falta declarar nada de eso a mano acá.
  programs.niri.enable = true;

  # El módulo pasa enableXWayland=false a propósito (niri no usa el Xwayland
  # "rootful" clásico) pero NO instala xwayland-satellite -- confirmado grepeando
  # nixos/modules/programs/wayland/niri.nix, sin ninguna referencia a xwayland ahí.
  # niri >= 25.08 (acá 26.04) integra xwayland-satellite solo SI está en PATH: crea
  # los sockets X11, exporta $DISPLAY y lo lanza on-demand al primer cliente X11.
  # Sin esto, cualquier app que necesite X11 (IntelliJ IDEA, TeXstudio, LibreOffice,
  # Steam) falla en silencio. Verificar con el log "listening on X11 socket: :0".
  #
  # swaybg: workaround para un bug real de DMS/quickshell sin arreglo confirmado
  # upstream (AvengeMedia/DankMaterialShell#2299) -- la superficie de fondo propia
  # de DMS a veces queda gris en el escritorio normal (el Overview sí pinta bien).
  # swaybg dibuja una segunda superficie que gana el z-order y sí se ve.
  #
  # dms-wallpaper-watch (definido acá abajo, spawn real en home/ale/niri.kdl):
  # swaybg por sí solo lee la ruta del wallpaper UNA sola vez al arrancar -- sin
  # esto, cambiar de wallpaper desde la propia UI de DMS no se veía en el
  # escritorio normal (solo en el Overview, que pinta la superficie real de DMS,
  # no la de swaybg) hasta reiniciar niri. Diagnosticado en vivo (2026-08-10):
  # confirmado con `dms ipc call wallpaper set <ruta>` que session.json se
  # actualiza al instante pero el swaybg ya corriendo se queda con la ruta vieja.
  # Este script vigila session.json con inotify y relanza swaybg con la ruta
  # nueva cada vez que cambia -- así el workaround queda dinámico de verdad.
  #
  # Se vigila el DIRECTORIO, no el archivo directo -- confirmado en vivo con
  # `inotifywait -m` que DMS escribe session.json con el patrón atómico
  # temp-file+rename (CREATE session.json.XXXXXX, después MOVED_TO
  # session.json), no in-place. Un watch sobre la ruta del archivo queda
  # apuntando al inode viejo (ya eliminado por el rename) y nunca vuelve a
  # disparar -- confirmado que watchear el archivo directo con close_write/
  # moved_to NO detectaba nada, ni un solo evento en varias pruebas.
  environment.systemPackages = [
    pkgs.xwayland-satellite
    pkgs.swaybg
    pkgs.jq
    (pkgs.writeShellScriptBin "dms-wallpaper-watch" ''
      set -u
      statedir="$HOME/.local/state/DankMaterialShell"
      session="$statedir/session.json"
      current=""
      swaybg_pid=""
      while true; do
        path=$(${pkgs.jq}/bin/jq -r '.wallpaperPath // empty' "$session" 2>/dev/null || true)
        if [ -n "$path" ] && [ "$path" != "$current" ] && [ -f "$path" ]; then
          # Matar por PID guardado, NO por nombre de proceso -- el binario
          # de pkgs.swaybg corre como `.swaybg-wrapped` (wrapper de Nix),
          # no como `swaybg` -- `pkill -x swaybg` nunca matcheaba nada
          # (confirmado en vivo: quedaban instancias viejas acumulándose,
          # una por cada cambio de wallpaper, en vez de reemplazarse).
          if [ -n "$swaybg_pid" ]; then
            kill "$swaybg_pid" 2>/dev/null || true
          fi
          # Sin `-o`: swaybg pinta TODAS las salidas conectadas (y las que se
          # enchufen después) con la misma imagen. Con `-o eDP-1` el monitor
          # externo por HDMI se quedaba sin fondo -- la superficie propia de
          # DMS que debería cubrirlo está rota en el escritorio normal (mismo
          # bug #2299 que motiva este workaround).
          ${pkgs.swaybg}/bin/swaybg -i "$path" -m fill &
          swaybg_pid=$!
          current="$path"
        fi
        # --include filtra el directorio para reaccionar solo a session.json
        # (DMS también reescribe otros archivos de estado ahí, ej. colores).
        # Patrón simple a propósito -- probado en vivo que un regex anclado
        # y escapado ('^session\.json$') NO matcheaba nunca con esta versión
        # de inotify-tools (el proceso se quedaba esperando para siempre,
        # confirmado con `dms ipc call wallpaper set` real de por medio); el
        # patrón sin anclas sí funciona, y no hay otro archivo en este
        # directorio cuyo nombre contenga "session.json".
        # El `|| sleep 2` es la red de seguridad si inotify fallara por algún
        # motivo (ej. inotify_add_watch sin descriptores libres) -- cae a
        # polling en vez de quedarse colgado sin reintentar nunca.
        ${pkgs.inotify-tools}/bin/inotifywait -qq -e moved_to -e close_write \
          --include 'session.json' "$statedir" 2>/dev/null || sleep 2
      done
    '')

    # --- Presentar con espejo (proyector) ---
    # niri NO espeja salidas de forma nativa. wl-mirror captura eDP-1 y la
    # muestra fullscreen en la pantalla externa: presentás con `slides` (u otra
    # cosa) mirando el portátil y controlando con el teclado, y el público ve
    # la misma imagen en el proyector. Funciona con el Kitty Graphics Protocol
    # del fork de slides (captura a nivel compositor, no del stream de la
    # terminal -- por eso NO sirve tmux acá). Bind Mod+Shift+P en niri.kdl;
    # volver a pulsarlo corta el espejo.
    #
    # El destino se autodetecta (primera salida conectada que NO sea eDP-1),
    # así funciona con cualquier proyector/monitor sin importar si el conector
    # es HDMI-A-1, DP-1 (adaptador USB-C), etc.
    pkgs.wl-mirror
    (pkgs.writeShellScriptBin "present-mirror" ''
      if ${pkgs.procps}/bin/pkill -f 'wl-mirror .*--fullscreen-output'; then
        exit 0
      fi
      target=$(${config.programs.niri.package}/bin/niri msg --json outputs \
        | ${pkgs.jq}/bin/jq -r 'to_entries[] | select(.key != "eDP-1" and .value.current_mode != null) | .key' \
        | head -n1)
      if [ -z "$target" ]; then
        ${pkgs.libnotify}/bin/notify-send "present-mirror" "No hay pantalla externa conectada" || true
        exit 1
      fi
      exec ${pkgs.wl-mirror}/bin/wl-mirror --fullscreen-output "$target" eDP-1
    '')
  ];

  # --- DankMaterialShell ---
  # Módulo NixOS del flake propio de DMS (dank-material-shell.nixosModules.default,
  # agregado en flake.nix), NO el de nixpkgs (programs.dms-shell): se eligió el
  # flake por los settings/session declarativos del módulo home-manager y por
  # lockscreen.securityKey (desbloqueo de la lockscreen con la YubiKey, que este
  # equipo ya usa para GPG/SSH -- ver modules/yubikey.nix).
  programs.dank-material-shell = {
    enable = true;

    # systemd.enable = true (NO combinado con spawn-at-startup en niri.kdl --
    # se sacó de ahí a propósito, ver ese archivo). El unit real
    # (assets/systemd/dms.service de DMS) trae `Restart = "on-failure"`, que es
    # justo lo que faltó cuando se probó en vivo (2026-08-08): un `dms restart`
    # mató el proceso y NADA lo relanzó -- pantalla sin barra/dock/wallpaper
    # hasta que se relanzó a mano. El unit es wantedBy=graphical-session.target,
    # que niri-session activa solo (corre dbus-update-activation-environment y
    # arranca niri.service, BindsTo=/Before=graphical-session.target --
    # confirmado contra resources/niri-session y resources/niri.service reales
    # del proyecto, y en vivo con `systemctl --user is-active
    # graphical-session.target` -> active).
    systemd.enable = true;

    lockscreen.securityKey.enable = true;
  };

  # --- Nvidia + niri: VRAM no liberado ---
  # Quirk documentado en niri-wm.github.io/niri/Nvidia.html: el driver propietario
  # no devuelve VRAM al pool bajo compositores Wayland, y niri lo sufre -- uso
  # normal ~100 MiB, sin este perfil sube a ~1 GiB. Relevante en este equipo por la
  # GTX 1050 (Pascal, legacy_580) en PRIME sync de modules/graphics.nix. JSON exacto
  # tomado de la doc oficial, sin modificar.
  environment.etc."nvidia/nvidia-application-profiles-rc.d/50-limit-free-buffer-pool-in-wayland-compositors.json".text = builtins.toJSON {
    rules = [
      {
        pattern = {
          feature = "procname";
          matches = "niri";
        };
        profile = "Limit Free Buffer Pool On Wayland Compositors";
      }
    ];
    profiles = [
      {
        name = "Limit Free Buffer Pool On Wayland Compositors";
        settings = [
          {
            key = "GLVidHeapReuseRatio";
            value = 0;
          }
        ];
      }
    ];
  };
}
