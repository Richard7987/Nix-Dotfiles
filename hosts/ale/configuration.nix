{ config, pkgs, lib, inputs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/graphics.nix
    ../../modules/yubikey.nix
    ../../modules/tailscale.nix
    ../../modules/desktop.nix
  ];

  # --- Boot ---
  # Asume arranque UEFI (normal en cualquier laptop de los últimos ~10 años).
  # Si tu equipo arranca en modo BIOS/legacy (raro, pero posible), esto va a
  # fallar al instalar el bootloader -- en ese caso cambia por:
  #   boot.loader.grub.enable = true;
  #   boot.loader.grub.device = "/dev/sdX";  # disco completo, no partición
  # y quita las dos líneas de systemd-boot/efi de abajo.
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 5;
  boot.loader.efi.canTouchEfiVariables = true;

  # Sin esto no hay swap en absoluto (hardware-configuration.nix trae
  # swapDevices = [ ]), y systemd-oomd queda "degradado" bajo presión de
  # memoria (no puede intervenir a tiempo vía PSI). Resultado observado:
  # el sistema se puso cada vez más lento hasta quedar totalmente
  # colgado (journald "Under memory pressure, flushing caches", D-Bus
  # timeouts al intentar suspender) sin que el OOM-killer llegara a
  # dispararse, forzando un apagado por hardware. zram le da a oomd un
  # swap comprimido en RAM para reclamar memoria a tiempo.
  zramSwap.enable = true;

  # --- Red ---
  networking.hostName = "ale";
  # networking.networkmanager.enable ya se activa en modules/desktop.nix (requisito de Noctalia)

  # --- Zona horaria / locale ---
  time.timeZone = lib.mkDefault "America/Mexico_City"; # AJUSTAR si no es tu zona
  i18n.defaultLocale = "es_MX.UTF-8";

  # --- Usuario ---
  users.users.ale = {
    isNormalUser = true;
    description = "ale";
    extraGroups = [ "wheel" "networkmanager" "video" "input" "dialout" ];
    shell = pkgs.zsh;
  };
  programs.zsh.enable = true;

  # --- Nix ---
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nixpkgs.config.allowUnfree = true; # necesario para el driver Nvidia y Steam

  # Binary cache oficial de Noctalia -- sin esto, cada rebuild compila
  # Noctalia desde fuente en vez de bajar el binario prearmado
  # (docs.noctalia.dev/v5/getting-started/nixos).
  #
  # Binary cache oficial de Psysonic (nixos-install.md del repo real, no
  # nixpkgs) -- sin esto, cada rebuild compila el frontend (npm) y el
  # binario Tauri (Rust) desde cero en vez de bajarlos ya armados. La build
  # que disparó este agregado (primer switch tras el cambio Feishin →
  # Psysonic) ya venía compilando en local antes de que esto se agregara --
  # no la acelera retroactivamente, pero sí los rebuilds futuros.
  nix.settings.extra-substituters = [
    "https://noctalia.cachix.org"
    "https://psysonic.cachix.org"
  ];
  nix.settings.extra-trusted-public-keys = [
    "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
    "psysonic.cachix.org-1:M9cQyQ7tgvUWOQ5Pyt8ozlMoPLtOZir6MfRuTH9/VYA="
  ];

  # Sin esto /nix/store solo crece: no había ningún GC programado, y
  # boot.loader.systemd-boot.configurationLimit (ver más abajo) solo recorta
  # el menú de arranque, no el store. Semanal + 14 días de margen para poder
  # hacer rollback a una generación reciente si un rebuild sale mal.
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  # nix-ld: provee un linker dinámico genérico (+ libs comunes) para poder
  # correr binarios prebuilt de terceros sin patchear -- sin esto, cualquier
  # binario dinámicamente enlazado que un tool descargue por su cuenta (VSCode
  # extensions, npx, el language server de GitHub Copilot en Zed, etc.) falla
  # con "cannot execute: required file not found". Visto por primera vez con
  # el language server de Copilot en Zed.
  programs.nix-ld.enable = true;

  environment.systemPackages = with pkgs; [
    git
    vim
    curl
    wget
    claude-code
    clamav # da el binario `clamscan` que invoca clamui (pkgs/clamui.nix, instalado vía home.nix)
    uv # da `uvx` -- lanza el server MCP de kinocut (pip install kinocut aislado, sin venv manual)
    ffmpeg # kinocut llama a los binarios ffmpeg/ffprobe por PATH -- mpv (modules/desktop.nix)
           # linkea libav* como librería interna, pero no expone esos binarios sueltos.
    appimage-run # ejecuta el AppImage de idevice_pair (pairing con iPhone para SideStore)
  ];

  # usbmuxd: demonio que expone el iPhone conectado por USB como socket local
  # (/var/run/usbmuxd) -- sin esto, idevice_pair no encuentra el dispositivo.
  services.usbmuxd.enable = true;

  # Mantiene las firmas de virus actualizadas (freshclam) -- sin esto,
  # clamscan/clamui funcionan pero con una base de datos que envejece.
  services.clamav.updater.enable = true;

  # --- ccache: cachea objetos compilados de C/C++ entre builds ---
  # OJO con el alcance real: ccache acelera SOLO compilación C/C++/Objective-C
  # (gcc/clang), no Rust (librepods, pkgs/librepods.nix) ni Python puro
  # (clamui). packageNames hace un `super.<pkg>.override { stdenv =
  # ccacheStdenv; }` sobre el atributo top-level nombrado que le agregues acá
  # -- vacío por ahora, no hay ningún paquete C/C++ "plano" propio en este
  # repo todavía que se beneficie.
  programs.ccache = {
    enable = true;
    packageNames = [ ];
  };

  # ccache necesita reusar su directorio de cache entre builds -- el sandbox
  # de Nix aísla el filesystem de cada build por defecto, lo que anularía el
  # cache. extra-sandbox-paths expone SOLO este path puntual dentro del
  # sandbox (bind-mount), sin desactivar el sandbox para todo lo demás.
  nix.settings.extra-sandbox-paths = [ config.programs.ccache.cacheDir ];

  # NUNCA cambies este valor después de la instalación inicial (ver `man configuration.nix`,
  # sección system.stateVersion). Reemplázalo por el que te haya dado el instalador de NixOS
  # antes de correr el primer `nixos-rebuild switch`.
  system.stateVersion = "26.05";
}
