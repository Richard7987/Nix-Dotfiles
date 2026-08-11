{ config, lib, pkgs, ... }:

{
  # Gráficos duales Intel (iGPU) + Nvidia (dGPU) en modo PRIME "sync":
  # la Nvidia renderiza siempre y la Intel solo saca la imagen a pantalla.
  # Más consumo de batería que "offload", pero evita bugs de compositor en
  # pantallas externas/HDMI conectadas al puerto de la dGPU — lo pediste así
  # a propósito.
  #
  # AJUSTA los bus IDs de abajo a los reales de tu equipo. Para obtenerlos:
  #   lspci -D | grep -E "VGA|3D"
  # Ejemplo de salida:
  #   0000:00:02.0 VGA compatible controller: Intel Corporation ...
  #   0000:01:00.0 3D controller: NVIDIA Corporation ...
  # Fórmula del bus ID: "PCI:<bus-decimal>@<dominio-decimal>:<device-decimal>:<function-decimal>"
  #   00:02.0 (dominio 0000) -> intelBusId  = "PCI:0@0:2:0"
  #   01:00.0 (dominio 0000) -> nvidiaBusId = "PCI:1@0:0:0"
  # (Los valores de abajo son placeholders con el patrón más común en laptops;
  # verifícalos con el comando de arriba antes del primer rebuild.)

  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.graphics = {
    enable = true;
    enable32Bit = true; # necesario para Steam/Proton

    # VAAPI de la iGPU Intel -- sin esto, cualquier proceso que abra
    # /dev/dri/renderD128 (el nodo Intel, dueño real de la pantalla interna
    # en modo PRIME sync) y pida vaInitialize no tiene ningún driver que
    # cargar. Confirmado en vivo: gpu-screen-recorder (grabación de pantalla
    # vía Noctalia) fallaba con "vaInitialize failed" / "failed to query
    # supported video codecs for device /dev/dri/renderD128" -- ver el
    # wrapper en home/ale/home.nix sobre por qué esto solo no alcanzaba
    # (environment.sessionVariables.LIBVA_DRIVER_NAME más abajo fuerza el
    # driver de Nvidia incluso contra este nodo Intel).
    extraPackages = [ pkgs.intel-media-driver ];
  };

  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = true;

    # false = driver propietario. Es lo más estable hoy para CUDA y para GPUs
    # anteriores a Turing. Si tu GPU es RTX 20xx o más nueva puedes probar
    # open = true (módulo kernel open-source de Nvidia).
    open = false;

    # "stable" (595.84 al momento de escribir esto) dejó de soportar Pascal
    # (GP10x, incluye la GTX 1050 de esta laptop) -- confirmado en vivo:
    # `dmesg` mostraba "NVRM: No NVIDIA GPU found" y el módulo nvidia
    # cargaba pero sin bindear la GPU (lsmod sin nvidia, sin /dev/dri/card0
    # de nvidia, nvidia-smi fallaba). El propio log del kernel lo dice:
    # "supported through the NVIDIA 580.xx Legacy drivers". legacy_580
    # (580.173.02) es la rama correcta para Pascal.
    package = config.boot.kernelPackages.nvidiaPackages.legacy_580;

    prime = {
      sync.enable = true;
      # Confirmado contra hardware real: `lspci -D | grep -E "VGA|3D"` dio
      # 0000:00:02.0 (Intel) y 0000:01:00.0 (Nvidia).
      intelBusId = "PCI:0@0:2:0";
      nvidiaBusId = "PCI:1@0:0:0";
    };
  };

  # Variables recomendadas para Nvidia + Wayland en modo sync.
  # WLR_NO_HARDWARE_CURSORS (workaround típico de compositores wlroots +
  # Nvidia) sacado -- niri es Smithay, no wlroots, no lo lee; era para
  # Hyprland/noctalia-greeter, ambos ya removidos (Fase 3 de la migración a
  # niri+DMS, ver NOTES.md).
  environment.sessionVariables = {
    LIBVA_DRIVER_NAME = "nvidia";
    GBM_BACKEND = "nvidia-drm";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
  };

  # --- Gaming ---
  # Steam DESACTIVADO (2026-08-07, a pedido explícito). Todo el bloque queda
  # comentado en vez de borrado para poder reactivarlo con solo descomentar.
  # programs.steam = {
  #   enable = true;
  #   remotePlay.openFirewall = true;
  #   dedicatedServer.openFirewall = false;
  #
  #   # Proton-GE (GloriousEggroll) -- fork comunitario de Proton, mucho más
  #   # compatible que el Proton oficial de Steam para juegos recientes/raros
  #   # que todavía no tienen soporte oficial. Aparece en Steam como
  #   # "GE-Proton" en la lista de herramientas de compatibilidad por juego.
  #   extraCompatPackages = [ pkgs.proton-ge-bin ];
  #
  #   # Sesión Gamescope (el compositor de la Steam Deck) seleccionable desde
  #   # el display manager -- arregla bugs de pantalla completa/resolución en
  #   # varios juegos que no llevan bien correr directo sobre Hyprland.
  #   gamescopeSession.enable = true;
  # };
  programs.gamemode.enable = true;

  # --- CUDA ---
  # Paquete grande (varios GB). DESACTIVADO (2026-08-07): sin uso de ML/compute
  # en esta GPU por ahora y hacía falta liberar espacio (~8.5GB libres) para
  # el gaming (Proton-GE/Heroic, ver arriba). Descomentar si hace falta CUDA.
  environment.systemPackages = with pkgs; [
    # cudaPackages.cudatoolkit

    # Diagnóstico gráfico: glxinfo (mesa-demos) y vulkaninfo (vulkan-tools),
    # para confirmar en cualquier momento qué GPU está renderizando de verdad
    # (relevante en PRIME sync, donde la Nvidia debería aparecer como
    # renderer activo).
    mesa-demos
    vulkan-tools

    # mangohud # overlay de FPS/temperatura/uso de GPU -- activable por juego
             # desde las propiedades de lanzamiento de Steam ("Habilitar
             # overlay de MangoHud") o con `mangohud %command%`. DESACTIVADO
             # junto con proton-ge/gamescope/heroic por espacio en disco
             # (~8.5GB libres, 2026-08-07) -- descomentar junto con el resto.

    # Heroic Games Launcher (Epic Games Store + GOG) -- DESACTIVADO a
    # propósito: el disco tiene ~8.5GB libres (2026-08-07, `df -h /`) y no
    # alcanza ni para el launcher en uso normal (descargas de juegos vía
    # Epic/GOG se guardan aparte de la Nix store). Descomentar cuando haya
    # más espacio en disco.
    # heroic

    # Minecraft Java Edition. Reemplaza a prismlauncher (que sí estaba en
    # nixpkgs) por pedido explícito -- x-minecraft-launcher no tiene paquete
    # oficial en nixpkgs ni flake comunitario (confirmado buscando), así que
    # se empaqueta acá mismo desde el AppImage oficial. Ver
    # pkgs/x-minecraft-launcher.nix para el porqué del approach (AppImage
    # envuelto, no build desde fuente) y qué se confirmó en vivo.
    (callPackage ../pkgs/x-minecraft-launcher.nix { })
  ];
}
