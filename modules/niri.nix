{ config, lib, pkgs, ... }:

{
  # --- niri ---
  # Migración en curso desde Hyprland (ver NOTES.md/plan de migración) -- convive
  # como segunda sesión seleccionable en el greeter mientras se prueba, Hyprland
  # sigue intacto en modules/desktop.nix. El módulo de nixpkgs
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
  # swaybg + jq: workaround para un bug real de DMS/quickshell sin arreglo
  # confirmado upstream (AvengeMedia/DankMaterialShell#2299) -- la superficie de
  # fondo propia de DMS a veces queda gris en el escritorio normal (el Overview
  # sí pinta bien). swaybg dibuja una segunda superficie que gana el z-order y
  # sí se ve -- ver home/ale/niri.kdl para el spawn real, jq es lo que usa ese
  # spawn para leer la ruta actual del wallpaper del session.json de DMS.
  environment.systemPackages = [ pkgs.xwayland-satellite pkgs.swaybg pkgs.jq ];

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
    # hasta que se relanzó a mano. Confirmado seguro en ESTE equipo pese a que
    # Hyprland sigue instalado: el unit es wantedBy=graphical-session.target, y
    # ese target NUNCA se activa bajo Hyprland acá (por eso Noctalia necesitaba
    # el loop de shell, ver NOTES.md) -- así que no hay riesgo de que arranquen
    # dos instancias peleando por el bus, la advertencia de upstream sobre
    # combinar systemd+spawn no aplica a este caso. Bajo niri SÍ se activa
    # (niri-session corre dbus-update-activation-environment y arranca
    # niri.service, que es BindsTo=/Before=graphical-session.target --
    # confirmado contra resources/niri-session y resources/niri.service reales
    # del proyecto, y en vivo con `systemctl --user is-active graphical-session.target` -> active).
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
