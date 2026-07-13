# Notas de la migración FreeBSD → NixOS

Contexto y decisiones detrás de esta config, para no perder el hilo entre
sesiones. El README explica *cómo* desplegar; esto explica *por qué* está
armado así.

## Contexto

Esta es la misma PC que hoy corre FreeBSD 15.1 (laptop con gráficos duales
Intel + Nvidia, Optimus). El usuario instala NixOS por su cuenta; esta
config se preparó de antemano en la sesión de FreeBSD, sin acceso directo al
hardware real de la futura instalación NixOS — por eso varios valores quedan
marcados `AJUSTAR` (ver README).

Trae lo que ya se tenía funcionando en FreeBSD (YubiKey para GPG/SSH,
Tailscale con exit node de Mullvad, zen-browser, doas) más una capa gráfica
nueva: Hyprland + [Noctalia](https://docs.noctalia.dev/).

## Decisiones tomadas y por qué

- **Gráficos: PRIME *sync*, no *offload*.** La Nvidia renderiza siempre y la
  Intel solo saca la imagen a pantalla. Más consumo de batería que offload,
  pero el usuario lo pidió explícitamente para evitar bugs de compositor en
  pantallas externas/HDMI. Uso "serio" de gaming/CUDA → driver **propietario**
  (`hardware.nvidia.open = false`), Steam + gamemode + `cudaPackages.cudatoolkit`.
- **Greeter: `noctalia-greeter`, no SDDM/greetd genérico.** Es el greeter
  oficial de Noctalia (greetd + compositor wlroots propio), comparte tema y
  wallpaper con el shell. Se eligió tras confirmar que existe
  (`github:noctalia-dev/noctalia-greeter`) y que es justamente "el que mejor
  encaja con Noctalia", que era el criterio pedido.
- **Hyprland en Lua (`hyprland.lua`), no `hyprland.conf`.** Hyprland ≥0.55
  soporta config en Lua vía la API `hl.*`; confirmado vigente contra la
  documentación oficial y el wiki de Hyprland (no es una alucinación de
  versión).
- **`doas` en vez de `sudo`** (preferencia general del usuario, ya usada en
  FreeBSD). Reglas nopass para `tailscale` y para
  `systemctl restart pcscd.service` (esta última para que el comando
  `yubico` sea instantáneo).
- **Sin gestión de secretos (agenix/sops).** No hace falta: la clave GPG vive
  físicamente en la YubiKey, y Tailscale se autentica interactivo una sola
  vez (`doas tailscale up`); después `tailscale set --exit-node` persiste
  solo en el estado de `tailscaled` — no depende de que el usuario inicie
  sesión gráfica, y tampoco depende de ningún bug de driver wifi como en
  FreeBSD (`iwm0` fallando intermitente y bloqueando el boot).
- **Workarounds de FreeBSD que NO se copiaron tal cual:** `--disable-polkit`
  en pcscd y `disable-ccid` en scdaemon eran parches específicos de un bug de
  polkit en FreeBSD. En NixOS/Linux, `services.pcscd.enable = true` normal
  debería bastar. Se dejó `disable-ccid` en `scdaemonSettings` por las dudas,
  pero es probable que ni haga falta — si GPG/YubiKey funciona sin él,
  quitarlo.
- **Teclado: `us` + variante `altgr-intl`, no `latam` completo.** El usuario
  quiere QWERTY en inglés pero con `AltGr+n` → `ñ` y `AltGr+'` + vocal →
  tilde, en vez de cambiar todo el layout.
- **zen-browser: binario `zen-beta`, no `zen`.** El canal `default` del flake
  `0xc000022070/zen-browser-flake` apunta a beta, y el paquete instala el
  binario como `zen-${variante}` (verificado en el `package.nix` del flake).
- **Audio (pipewire/wireplumber)** se agregó después de un primer repaso: los
  atajos de volumen del `hyprland.lua` usan `wpctl`, que sin
  `services.pipewire.enable` no existe ni suena nada.

## Pendiente (`AJUSTAR` en el código, requiere la máquina real con NixOS ya instalado)

1. `hosts/ale/hardware-configuration.nix` — reemplazar por el que genera
   `nixos-generate-config`.
2. `system.stateVersion` / `home.stateVersion` — poner el valor real que dé
   el instalador (y no tocarlo nunca después).
3. `modules/graphics.nix` — bus IDs reales de Intel/Nvidia
   (`lspci -D | grep -E "VGA|3D"`).
4. `home/ale/hyprland.lua` — nombre real del monitor (`hyprctl monitors`,
   hoy con placeholder `"eDP-1"`).
5. Confirmar si los keybinds nativos de Noctalia (launcher/control
   center/settings) ya vienen solos al lanzar `noctalia`, o si hace falta
   declararlos a mano — bloque dejado comentado en `hyprland.lua` por
   incertidumbre (la doc de Noctalia no publica el comando IPC exacto).

## Auditoría (2026-07-12)

Repaso completo de todos los archivos para verificar sintaxis, opciones y
consistencia entre módulos. Se encontró y corrigió un bug real:

- **`home/ale/hyprland.lua`, atajos de workspace (mainMod+1..9):** usaba
  `hl.dsp.exec_raw("workspace " .. i)`. `exec_raw` es para lanzar programas
  sin las comillas del shell (equivalente al `execr` de Hyprland clásico),
  **no** para dispatchers de compositor — con eso Hyprland habría intentado
  ejecutar un programa llamado literalmente "workspace 1" en vez de cambiar
  de espacio. Corregido a `hl.dsp.focus({ workspace = tostring(i) })` para
  cambiar de workspace y `hl.dsp.window.move({ workspace = tostring(i) })`
  para mover la ventana enfocada — API confirmada contra la referencia de
  `hl.dsp.*` y el `hyprland.lua` de ejemplo del repo oficial de Hyprland.

## Auditoría exhaustiva #2 (2026-07-12) — contra código fuente real, no docs resumidas

Esta vuelta verifiqué cada módulo externo (Noctalia, noctalia-greeter,
zen-browser-flake, y los módulos de nixpkgs de hyprland/graphics/nvidia/
pipewire/doas) leyendo su `.nix` real en GitHub, no la página de docs (que
pasa por un resumidor y puede parafrasear mal un nombre de opción). Encontré
un bug grave y descarté un riesgo real que ya no era tal tras verificar:

- **BUG GRAVE, corregido:** nunca importé el módulo de home-manager de
  Noctalia (`inputs.noctalia.homeModules.default`) en `home/ale/home.nix` —
  solo el de NixOS. Sin ese import, la opción `programs.noctalia.*` que uso
  ahí (settings, systemd.enable) **no existe** en el esquema de home-manager
  y el build habría fallado con "The option `programs.noctalia.enable' does
  not exist". Confirmado leyendo `noctalia/flake.nix` (expone
  `homeModules.default` por separado de `nixosModules.default`, cada uno
  envolviendo un módulo `.nix` distinto) y `nix/home-module.nix` (que
  requiere `package` sin default propio — se resuelve solo si se usa el
  `homeModules.default` del flake, que sí trae `lib.mkDefault`). Ya agregado
  el `imports` que faltaba.
- **Blindaje agregado:** `home-manager.backupFileExtension = "hm-backup";`
  en `flake.nix` — sin esto, si algún archivo ya existiera donde
  home-manager quiere escribir uno declarativo (ej. si reinstalas o si algo
  crea `~/.config/hypr/hyprland.lua` a mano antes del primer switch), la
  activación completa falla en vez de hacer backup y seguir.
- **Parecía bug, no lo es (verificado):** el módulo de `noctalia-greeter`
  lee `config.services.greetd.settings.default_session.user` sin definirlo
  él mismo, y yo nunca lo seteo en `modules/desktop.nix`. Pero el módulo de
  greetd de NixOS sí lo defaultea a `"greeter"` automáticamente
  (`lib.mkDefault "greeter"`) apenas `services.greetd.enable = true` — y
  noctalia-greeter activa justo eso (`lib.mkDefault true`). Es un patrón de
  punto fijo perfectamente normal en el sistema de módulos de NixOS, no un
  ciclo roto. No hacía falta tocar nada.
- **Parecía bug, no lo es (verificado):** `services.pipewire` con
  `alsa.enable`/`pulse.enable` en `true` tiene una aserción que exige
  `audio.enable = true`. Pero `audio.enable` **defaultea** exactamente a
  `alsa.enable || jack.enable || pulse.enable`, así que se satisface solo.
  No hacía falta declarar `audio.enable` a mano.
- **Riesgo evaluado, descartado:** que `programs.hyprland.enable` (módulo
  in-tree de nixpkgs, sin flake propio de Hyprland como input) instalara una
  versión vieja de Hyprland sin soporte Lua. Confirmé contra
  `pkgs/by-name/hy/hyprland/package.nix` en nixpkgs `nixos-unstable`:
  versión **0.55.4**, que sí soporta `hyprland.lua`. No hizo falta agregar
  `hyprwm/Hyprland` como input aparte.
- Confirmado contra fuente real y sin cambios necesarios: `hardware.graphics.enable32Bit`
  (nombre correcto tras el rename de `hardware.opengl`), la condición de activación
  del módulo Nvidia (`elem "nvidia" services.xserver.videoDrivers`, no requiere
  `xserver.enable`), el formato de bus ID contra su regex real, el binario
  `zen-${name}` → `zen-beta` (visto en el `package.nix` real del flake), que
  `programs.hyprland.enable` ya configura `xdg.portal`/el wrapper de
  capacidades/la sesión del display manager solo, y que `security.doas` no
  tiene ninguna aserción que choque con dejar `security.sudo.enable = true`
  a la vez.

## Auditoría exhaustiva #3 (2026-07-12) — módulos de sistema (pcscd, gamemode, bluetooth, boot) + riesgo de doble lanzamiento de Noctalia

- **BUG real, corregido:** tenía `programs.noctalia.systemd.enable = true;`
  en `home/ale/home.nix` **a la vez** que lanzo Noctalia directamente desde
  `hl.on("hyprland.start", function() hl.exec_cmd("noctalia") end)` en
  `hyprland.lua` (que es el método que la propia doc de Noctalia documenta
  para Hyprland). El servicio systemd está ligado a
  `wayland.systemd.target` (default `"graphical-session.target"`, opción
  genérica de home-manager en `modules/wayland.nix`, confirmada que existe
  sin necesidad del módulo `wayland.windowManager.hyprland`). El problema no
  es que la opción no exista (sí existe), sino que si `graphical-session.target`
  llega a activarse por cualquier otro mecanismo (pam_systemd, logind, etc.)
  tendríamos DOS instancias de Noctalia arrancando: la del exec-once del
  compositor y la del servicio systemd, peleando por la barra/IPC. Solución:
  desactivé `systemd.enable` (queda en su default `false`) y me quedo solo
  con el exec-once, que es el mecanismo que no depende de si
  `graphical-session.target` se activa o no.
- Verificado contra el módulo real de **pcscd**
  (`services/hardware/pcscd.nix`): su paquete por defecto es
  `pcscliteWithPolkit` si `security.polkit.enable` está activo — y sí lo
  está (`programs.gamemode.enable = true` lo fuerza a `true` directamente,
  sin `mkDefault`, y el propio módulo de Hyprland también lo pone en `true`).
  Esto es normal en Linux/NixOS (a diferencia del polkit roto de FreeBSD) y
  no requiere ninguna acción; lo dejo anotado por si algún día ves un
  rechazo de acceso al lector y hay que mirar reglas de polkit en vez de
  copiar el workaround de FreeBSD.
- Verificado que `services.pcscd.enable = true` ya agrega
  `services.udev.packages = [ pkgs.ccid ]` por su cuenta — el
  `yubikey-personalization` que agrego en `modules/yubikey.nix` es
  complementario (reglas específicas de YubiKey, no genéricas de CCID), no
  redundante.
- Verificado `programs.gamemode.enable` (`programs/gamemode.nix`): no
  requiere agregar al usuario a ningún grupo adicional; solo hace falta
  `enable = true` como ya tengo.
- Verificado `hardware.bluetooth.powerOnBoot` — default `true` ya, no hacía
  falta declararlo (estuve a punto de agregarlo de más).
- Confirmado `cudaPackages.cudatoolkit` existe como atributo real en
  `pkgs/top-level/all-packages.nix` de nixpkgs unstable.
- **Gap de documentación, no de código:** `hosts/ale/configuration.nix`
  asume arranque UEFI (`systemd-boot` + `boot.loader.efi`). Si el equipo
  resulta ser BIOS/legacy (poco probable en un laptop moderno, pero
  posible), esto tumbaría la instalación del bootloader por completo. Dejé
  un comentario explícito en el archivo con el fallback a GRUB.

Se agregó **`claude-code`** a `environment.systemPackages` en
`hosts/ale/configuration.nix` (paquete oficial en nixpkgs, confirmado en
search.nixos.org) para tenerlo disponible sin depender de `nix run` cada vez.

Revisado sin encontrar problemas: merge de `environment.systemPackages`
repetido en varios módulos (es normal, NixOS concatena listas), orden de
reglas de `security.doas.extraRules` (doas usa "last match wins", por eso la
regla general va primero y las `noPass` específicas al final — sí es el
orden correcto), balance de llaves/paréntesis en `hyprland.lua`, y que
`services.xserver.videoDrivers = [ "nvidia" ]` no requiere
`services.xserver.enable = true` para que el módulo de Nvidia se active en un
sistema Wayland puro (patrón estándar en setups Hyprland+Nvidia).

## LibrePods (AirPods) (2026-07-12)

Investigué el repo (https://github.com/librepods-org/librepods, el real es
`kavishdevar/librepods` — el `-org` es un fork/mirror) antes de agregarlo.
Hallazgos clave:

- **No tiene flake.nix ni paquete Nix oficial.**
- El proyecto está a mitad de una reescritura: versión vieja en C++/Qt6
  (buildable con cmake, pero siendo reemplazada) vs. reescritura nueva en
  Rust (rama `linux/rust`, PR #241 sin mergear).
- Revisé los GitHub Releases vía la API (`api.github.com/repos/kavishdevar/
  librepods/releases`) y **todos los assets publicados son APKs de Android**
  — no hay ni un solo binario/AppImage de Linux en releases, pese a que el
  README dice "download from GitHub releases". La única forma de conseguir
  el binario de Linux es como *artifact* nightly de GitHub Actions
  (`ci-linux-rust.yml`), que están detrás de login y no tienen URL pública
  fija — por eso no es fijable con un hash reproducible en Nix sin más
  trabajo (habría que autenticarse a la API de Actions, algo que no puedo
  automatizar de forma limpia en una derivación).
- Ante ese trade-off (compilar la versión vieja Qt6 de forma 100%
  declarativa vs. usar el AppImage nuevo de forma manual), le pregunté al
  usuario — eligió el AppImage nuevo (versión Rust, más features).
- Lo que sí quedó automatizado: Bluetooth (ya estaba, `hardware.bluetooth.enable`
  en `modules/desktop.nix`), el fix de AVRCP para play/pause/skip
  (`~/.config/wireplumber/wireplumber.conf.d/51-bluez-avrcp.conf`, con
  reinicio de wireplumber vía `home.activation` en cada switch),
  `pkgs.appimage-run` y un alias `librepods` que lo invoca.
- **Pendiente manual del usuario, no automatizable:** descargar el AppImage
  de Actions y ponerlo en `~/Applications/LibrePods.AppImage` — instrucciones
  en el README. Cada vez que quiera actualizar, tiene que repetir el paso a
  mano (no hay manera limpia de automatizar esto sin que el proyecto
  publique releases de Linux reales).

## Auditoría exhaustiva #4 (2026-07-12) — el fix de AVRCP que acababa de agregar estaba mal ubicado

- **BUG real, corregido:** había puesto el fix de AVRCP de LibrePods
  (`monitor.bluez.properties = { bluez5.dummy-avrcp-player = true }`) como
  `xdg.configFile."wireplumber/wireplumber.conf.d/51-bluez-avrcp.conf"` en
  home-manager, siguiendo al pie de la letra la ruta que da el README de
  LibrePods (`~/.config/wireplumber/wireplumber.conf.d/`). Pero leyendo el
  módulo real de NixOS para wireplumber
  (`nixos/modules/services/desktops/pipewire/wireplumber.nix`), su config se
  inyecta vía `XDG_DATA_DIRS` apuntando a un paquete armado en el store de
  Nix (`services.pipewire.wireplumber.extraConfig`/`configPackages`) — el
  servicio systemd de wireplumber que gestiona NixOS no necesariamente lee
  `$HOME/.config/wireplumber/` de la forma en que yo asumía. El propio
  módulo trae un ejemplo de config de bluez casi idéntico al mío usando
  `configPackages`/`extraConfig`, lo cual confirma que esa es la vía
  soportada/esperada en NixOS. Moví el fix a
  `services.pipewire.wireplumber.extraConfig."51-bluez-avrcp"` en
  `modules/desktop.nix` (forma Nix nativa, tipada) y de paso pude quitar el
  hack de `home.activation` que reiniciaba wireplumber a mano (ya no hace
  falta: al ser config de sistema, `nixos-rebuild switch` la aplica solo).
- Verificado sin encontrar más problemas: `kdePackages.kleopatra` (existe en
  `pkgs/kde/gear/kleopatra`, agregado al set `kdePackages`),
  `nerd-fonts.jetbrains-mono` (confirmado contra
  `pkgs/data/fonts/nerd-fonts/manifests/fonts.json` — el `caskName` real es
  literalmente `"jetbrains-mono"`, con guion), y `pkgs.appimage-run` (existe
  en `pkgs/top-level/all-packages.nix`).

## Auditoría exhaustiva #5 (2026-07-12) — doas leído completo (no solo grep de opciones) + cambio a sudo

- **Riesgo real, corregido:** leyendo el módulo `security/doas.nix` completo
  (no solo los campos usados, como en rondas anteriores) encontré que el
  propio módulo agrega automáticamente una regla para el grupo `wheel` vía
  `lib.mkOrder 600`, y su documentación advierte explícitamente: *"More
  specific rules should come after more general ones... You can use
  mkBefore and/or mkAfter to ensure this is the case when configuration
  options are merged."* Mi `extraRules` era una lista plana (prioridad por
  defecto 1000), que en este caso concreto SÍ terminaba después de la regla
  `wheel` (600 < 1000) — funcionaba, pero por una coincidencia numérica, no
  por diseño. Lo envolví en `lib.mkAfter` para que sea correcto por
  construcción y no dependa de esa coincidencia si algo cambia.
- **Riesgo real, corregido:** los `cmd = "systemctl"` / `cmd = "tailscale"`
  usaban nombres relativos. La doc de la opción dice explícitamente: *"It is
  best practice to specify absolute paths. If a relative path is specified,
  only a restricted PATH will be searched"* — en NixOS los binarios no viven
  en `/usr/bin`/`/bin` (el PATH restringido típico de doas), así que un
  nombre relativo podía no resolver y silenciosamente pedir contraseña en
  vez de ser nopass. Cambiado a rutas absolutas
  (`/run/current-system/sw/bin/...`).
- **Falsa alarma descartada:** temí que `inputs.zen-browser.packages.
  ${system}.default` fallara porque el flake de zen-browser arma su propio
  `pkgs` internamente (`import nixpkgs {}` sin mi `nixpkgs.config.
  allowUnfree`). Revisé el `package.nix` real: `meta` **no tiene campo
  `license`** en absoluto, así que no hay ningún gate de unfree que
  satisfacer — no hacía falta ningún cambio.
- **A pedido del usuario:** cambiado `doas` → `sudo` en toda la config
  (`modules/yubikey.nix`, comentarios en `modules/tailscale.nix`,
  `home/ale/home.nix`, `README.md`). `ale` ya está en el grupo `wheel`, así
  que el acceso general con contraseña sale gratis de la regla por defecto
  del módulo de sudo — solo agregué las dos reglas `NOPASSWD` puntuales
  (pcscd, tailscale) que sí tenía con doas, con `lib.mkAfter` y rutas
  absolutas por la misma razón de arriba. Sintaxis de
  `security.sudo.extraRules` verificada contra `security/sudo.nix` (nota: en
  sudoers, especificar un comando SIN argumentos = argumentos libres —
  al revés de cómo se lograba en doas con `args = null`).
- De paso encontré una inconsistencia vieja: el README todavía describía el
  mecanismo de AVRCP como `xdg.configFile` en home-manager, aunque ya lo
  había movido a `services.pipewire.wireplumber.extraConfig` en la ronda
  anterior — corregido.

## Auditoría exhaustiva #6 (2026-07-12) — integración de Noctalia con el resto del sistema

Pedido explícito de revisar que todo lo que Noctalia trae preconfigurado
encaje bien con el resto. Investigué el **código fuente real** de
`noctalia-dev/noctalia` (no solo la doc): resulta que es una app **nativa en
C++/meson** (Wayland + OpenGL ES directo, no QML/Quickshell como asumía por
el nombre "shell"). Esto cambió varias suposiciones:

- **Pantalla de bloqueo:** existe (`src/shell/lockscreen/`), con
  autenticación PAM propia (`src/auth/pam_authenticator.cpp`). Rastreé el
  código hasta `lock_screen.cpp`: usa el servicio PAM **`"login"`**
  hardcodeado (no un servicio custom tipo `noctalia`/`noctalia-lock`).
  `security.pam.services.login` ya viene por defecto en cualquier NixOS —
  **no hace falta agregar nada.** (Comentario en el código fuente, para
  quien le interese: ignoran `PAM_AUTHINFO_UNAVAIL` porque un locker sin
  privilegios no puede leer `/etc/shadow` para el stack de `account`.)
- **Idle/auto-lock:** Noctalia trae su propio `idle_manager`
  (`src/idle/idle_manager.cpp`), no depende de `hypridle` ni de nada externo
  — no hacía falta agregarlo.
- **Red/Bluetooth/audio en el control center:** usa D-Bus de NetworkManager,
  BlueZ y PipeWire/WirePlumber directamente (`pipewire` y `wireplumber`
  están en `buildInputs` de `nix/package.nix`), todo ya cubierto por
  `networking.networkmanager.enable`, `hardware.bluetooth.enable` y
  `services.pipewire` que ya tenía.
- **Sesión de `noctalia-greeter` → Hyprland:** terminé de rastrear la
  incertidumbre que había dejado pendiente en rondas anteriores. El
  matching de `--session` en `greeter_sessions.cpp` es contra el campo
  `Name=` del `.desktop` (no el nombre de archivo), case-insensitive. El
  `.desktop` real de Hyprland (`example/hyprland.desktop.in` en
  `hyprwm/Hyprland`) tiene `Name=Hyprland`. **Confirmado: `--session
  hyprland` sí matchea.** Ya no es una suposición, quité la advertencia del
  comentario.
- Nada de esto requirió cambios de código salvo actualizar el comentario de
  `greeter-args` en `modules/desktop.nix` — todo lo demás ya estaba
  correctamente cubierto por la config existente.

### Nota aparte: DNS de Tailscale intermitente en esta sesión (FreeBSD)

Durante esta ronda se cayó la resolución de MagicDNS (100.100.100.100) dos
veces (confirmé con `tailscale netcheck` que la conectividad UDP/DERP
estaba sana — el problema era solo el resolver). El fix documentado en
[[tailscale_setup]] (`tailscale set --accept-dns=false` luego `=true`) no
lo arregló al toque la segunda vez; se resolvió solo unos segundos después.
Vale la pena vigilar si se repite seguido — podría ser algo nuevo, no
necesariamente el mismo mecanismo ya documentado.

## Auditoría exhaustiva #7 (2026-07-12) — dos preguntas reales al usuario + verificaciones finales

- **Idioma del sistema:** tenía `i18n.defaultLocale = "en_US.UTF-8"` puesto
  sin confirmarlo — afecta el idioma de casi todas las apps GTK/Qt (Noctalia,
  Kleopatra, etc.), no solo formato de fecha/moneda. Le pregunté al usuario:
  eligió español. Cambiado a `es_MX.UTF-8` (coherente con
  `time.timeZone = "America/Mexico_City"`). El teclado se queda en
  `us+altgr-intl` como ya estaba — layout de teclado e idioma del sistema son
  independientes, no hay conflicto.
- **Huella digital:** revisando `src/auth/fingerprint_authenticator.cpp` de
  Noctalia vi que su pantalla de bloqueo soporta desbloqueo por huella vía
  D-Bus (`net.reactivated.Fprint`, la interfaz estándar de `fprintd`) si el
  sistema lo tiene habilitado (`services.fprintd.enable`). Le pregunté al
  usuario si su laptop tiene lector — no tiene, así que no se agregó nada.
- Verificado sin encontrar problemas: consistencia de argumentos de función
  (`lib`/`inputs`/`pkgs`/`config`) en los 8 archivos `.nix` del repo tras
  todas las rondas de ediciones — ningún uso de un argumento que no esté en
  la firma. Y `hardware.nvidia.package = ...nvidiaPackages.stable` — 
  confirmado como atributo real contra
  `pkgs/os-specific/linux/nvidia-x11/default.nix` (en x86_64-linux resuelve
  internamente a `production`).

## Referencias usadas

- https://docs.noctalia.dev/v5/getting-started/nixos/
- https://docs.noctalia.dev/v5/compositor-settings/hyprland/
- https://github.com/noctalia-dev/noctalia (código fuente: `src/auth`,
  `src/idle`, `src/shell/lockscreen`, `nix/package.nix`)
- https://github.com/noctalia-dev/noctalia-greeter (código fuente:
  `src/greeter/greeter_sessions.cpp`, `src/main.cpp`)
- https://github.com/hyprwm/Hyprland (`example/hyprland.desktop.in`)
- https://github.com/0xc000022070/zen-browser-flake
- https://wiki.hypr.land/Nix/Hyprland-on-NixOS/
- https://hypr.land/news/26_lua/ (Lua-ificación de la config de Hyprland)
- Código fuente real de los módulos de home-manager (`programs/gpg.nix`,
  `services/gpg-agent.nix`, `programs/git.nix`) y de NixOS
  (`security/doas.nix`, `hardware/video/nvidia.nix`) — opciones verificadas
  ahí, no de memoria.
