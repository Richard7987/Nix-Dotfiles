{ config, pkgs, lib, inputs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/graphics.nix
    ../../modules/yubikey.nix
    ../../modules/tailscale.nix
    ../../modules/desktop.nix
    ../../modules/niri.nix
  ];

  # --- Boot ---
  # Asume arranque UEFI (normal en cualquier laptop de los últimos ~10 años).
  # Si tu equipo arranca en modo BIOS/legacy (raro, pero posible), esto va a
  # fallar al instalar el bootloader -- en ese caso cambia por:
  #   boot.loader.grub.enable = true;
  #   boot.loader.grub.device = "/dev/sdX";  # disco completo, no partición
  # y quita las dos líneas de systemd-boot/efi de abajo.
  boot.loader.systemd-boot.enable = true;
  # 2 = generación actual + la anterior en el menú de arranque, para poder
  # volver si un rebuild deja el sistema roto.
  boot.loader.systemd-boot.configurationLimit = 2;
  boot.loader.efi.canTouchEfiVariables = true;
  # El menú de systemd-boot esperaba los 5s por defecto en cada arranque. 1s
  # sigue alcanzando para colarse a elegir la generación anterior si hace
  # falta (mantené Espacio/flechas apretado al encender).
  boot.loader.timeout = lib.mkDefault 1;

  # Arranque silencioso: sin esto la consola escupe mensajes del kernel y de
  # cada unidad de systemd sobre fondo negro, y al pasar a la sesión se ve un
  # instante de texto de niri arriba a la izquierda antes de que pinte. quiet
  # + estos log-levels dejan la pantalla limpia hasta que aparece el
  # compositor (los errores siguen quedando en el journal).
  boot.kernelParams = [ "quiet" "udev.log_level=3" "rd.udev.log_level=3" "systemd.show_status=auto" ];
  boot.consoleLogLevel = 3; # NixOS lo traduce a loglevel=3 en la cmdline
  boot.initrd.verbose = false;

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
  # networking.networkmanager.enable ya se activa en modules/desktop.nix (lo usa el applet de red de DMS)

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

  # Binary cache oficial de Psysonic (nixos-install.md del repo real, no
  # nixpkgs) -- sin esto, cada rebuild compila el frontend (npm) y el
  # binario Tauri (Rust) desde cero en vez de bajarlos ya armados. La build
  # que disparó este agregado (primer switch tras el cambio Feishin →
  # Psysonic) ya venía compilando en local antes de que esto se agregara --
  # no la acelera retroactivamente, pero sí los rebuilds futuros.
  nix.settings.extra-substituters = [
    "https://psysonic.cachix.org"
  ];
  nix.settings.extra-trusted-public-keys = [
    "psysonic.cachix.org-1:M9cQyQ7tgvUWOQ5Pyt8ozlMoPLtOZir6MfRuTH9/VYA="
  ];

  # GC diario, conservando solo lo de los últimos 3 días -- con rebuilds ~1/día
  # eso deja la generación actual y la anterior (las que muestra
  # configurationLimit = 2), suficiente para hacer rollback si algo sale mal,
  # sin dejar que el store se acumule como antes.
  nix.gc = {
    automatic = true;
    dates = "daily";
    options = "--delete-older-than 3d";
  };

  # Deduplica ficheros idénticos del store con hardlinks al escribirlos. En un
  # store grande (multitud de closures de nixpkgs que solo difieren en unos
  # pocos paths tras cada `nix flake update`) recupera un 5-20%. Coste: un
  # hash extra por fichero nuevo al construir, despreciable. Para el store que
  # ya está acumulado hay que correr `nix store optimise` una vez a mano.
  nix.settings.auto-optimise-store = true;

  # GC de emergencia DURANTE un build: si el espacio libre baja de min-free,
  # Nix recolecta basura hasta llegar a max-free antes de seguir -- evita que
  # `nixos-rebuild` reviente con "No space left on device" a mitad de camino.
  nix.settings.min-free = 3 * 1024 * 1024 * 1024;   #  3 GiB
  nix.settings.max-free = 15 * 1024 * 1024 * 1024;  # 15 GiB

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
    clamav # da el binario `clamscan` que invoca clamui (pkgs/clamui.nix, instalado vía home.nix)
    uv # da `uvx` -- lanza el server MCP de kinocut (pip install kinocut aislado, sin venv manual)
    ffmpeg # kinocut llama a los binarios ffmpeg/ffprobe por PATH -- mpv (modules/desktop.nix)
           # linkea libav* como librería interna, pero no expone esos binarios sueltos.
    appimage-run # ejecuta el AppImage de idevice_pair (pairing con iPhone para SideStore)
    wineWow64Packages.stable # Wine 64/32-bit -- para correr el instalador de PASCO Capstone (PEC forense)
    winetricks # configura dependencias/componentes dentro del prefix de Wine
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
