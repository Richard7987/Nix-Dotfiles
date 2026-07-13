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
  };

  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = true;

    # false = driver propietario. Es lo más estable hoy para CUDA y para GPUs
    # anteriores a Turing. Si tu GPU es RTX 20xx o más nueva puedes probar
    # open = true (módulo kernel open-source de Nvidia).
    open = false;

    package = config.boot.kernelPackages.nvidiaPackages.stable;

    prime = {
      sync.enable = true;
      # Confirmado contra hardware real: `lspci -D | grep -E "VGA|3D"` dio
      # 0000:00:02.0 (Intel) y 0000:01:00.0 (Nvidia).
      intelBusId = "PCI:0@0:2:0";
      nvidiaBusId = "PCI:1@0:0:0";
    };
  };

  # Variables recomendadas para Nvidia + Wayland/Hyprland en modo sync
  environment.sessionVariables = {
    LIBVA_DRIVER_NAME = "nvidia";
    GBM_BACKEND = "nvidia-drm";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    WLR_NO_HARDWARE_CURSORS = "1";
  };

  # --- Gaming ---
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = false;
  };
  programs.gamemode.enable = true;

  # --- CUDA ---
  # Paquete grande (varios GB). Quítalo si al final no haces ML/compute con la GPU.
  environment.systemPackages = with pkgs; [
    cudaPackages.cudatoolkit
  ];
}
