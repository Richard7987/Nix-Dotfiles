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

## Auditoría exhaustiva #8 (2026-07-12) — `example.toml` real de Noctalia contra mi `settings`, y un agente de polkit faltante

- **BUG real, corregido:** ningún componente de la config (Hyprland,
  gamemode) activa un *agente* gráfico de polkit -- solo el *daemon*
  (`security.polkit.enable = true`, que arrancan ambos por su cuenta). Sin
  agente, cualquier acción de una app GUI que pida privilegios vía polkit
  (ej. NetworkManager guardando la contraseña de una red wifi) se queda
  colgada o falla en silencio, porque no hay ningún diálogo que la
  autorice. Noctalia trae su propio agente
  (`src/shell/polkit/polkit_panel.cpp`), pero viene **apagado por
  defecto** (`polkit_agent = false` en `example.toml`). Agregado
  `shell.polkit_agent = true` a `programs.noctalia.settings` en
  `home/ale/home.nix`.
- **Verificado, no hacía falta tocar nada:** temí que `shell.lang` tuviera
  que setearse a mano para que Noctalia saliera en español ahora que cambié
  `i18n.defaultLocale`. Rastreado hasta `i18n_service.cpp`: si no hay
  `lang` explícito en el TOML, cae a `$LANG`/`$LC_ALL`/`$LC_MESSAGES` del
  sistema -- y confirmé que existe `assets/translations/es.json` en el repo
  de Noctalia. La cadena completa (`i18n.defaultLocale` → `$LANG` →
  detección automática de Noctalia → catálogo `es.json`) ya funciona sin
  configuración adicional.
- **Verificado mis claves de `theme` contra el `example.toml` real** (no
  contra la doc, contra el archivo que el propio proyecto usa como
  referencia de defaults): `mode`, `source`, `builtin = "Catppuccin"`
  coinciden exactamente, incluyendo que `"Catppuccin"` es uno de los
  valores válidos del enum documentado ahí mismo.
- **Nota sobre seguridad de esta config:** `programs.noctalia.settings` con
  `validateConfig = true` (default) corre `noctalia config validate` sobre
  el TOML generado **en tiempo de build** (dentro de la derivación
  `noctalia-config`). Si algún nombre de clave que puse está mal, el build
  falla ahí con un error claro en vez de fallar en silencio en runtime --
  vale la pena saber esto si algún día ves fallar específicamente esa
  derivación.

## Auditoría exhaustiva #9 (2026-07-12) — sintaxis validada con herramientas reales + búsqueda de problemas conocidos

A pedido explícito de "revisa toda la sintaxis" en vez de solo leer:

- **Los 8 archivos `.nix` del repo pasan un checker de balance de
  llaves/paréntesis/corchetes/strings** escrito para la ocasión (Perl, en
  `/tmp/.../nix_balance_check.pl` -- consciente de comentarios `#`, `/* */`,
  strings `"..."` y `''...''` con interpolación `${}`). No reemplaza a
  `nix flake check` (no hay Nix instalado en esta sesión de FreeBSD), pero
  es una validación estructural real, no solo lectura visual.
- **`home/ale/hyprland.lua` pasa `luac54 -p`** (parser real de Lua 5.4, sin
  ejecutar) sin errores -- sintácticamente válido de verdad. `stylua
  --check` solo marcó diferencias de tabs-vs-espacios (estilo, no bugs);
  se dejó como está porque 2 espacios es consistente con el resto del repo.
- **BUG real, corregido:** buscando problemas conocidos de Hyprland+Nvidia y
  de noctalia-greeter encontré que `pkexec` necesita el wrapper setuid de
  NixOS (`security.polkit.enablePkexecWrapper`, default `false`) para
  funcionar -- el binario crudo del store no tiene setuid. Releyendo el
  `gamemode.nix` que ya había verificado en la ronda #3, até el cabo que
  había dejado suelto: el servicio systemd de gamemode apunta su PATH a
  `"${security.wrapperDir}/pkexec"`, que **no existiría** sin ese flag --
  las operaciones privilegiadas de gamemode (cpugovctl/gpuclockctl)
  habrían fallado en silencio. De paso, esto es exactamente el problema
  documentado de noctalia-greeter ("Sync fails with no privilege
  escalator... pkexec disabled on NixOS") para su función "Sync Now".
  Agregado `security.polkit.enablePkexecWrapper = true` en
  `modules/desktop.nix`.
- **Verificado, no hacía falta cambiar nada:** el umbral de driver Nvidia
  ≥555 que documentan varios hilos de 2026 para "explicit sync" (evita
  flickering en XWayland con Hyprland) -- confirmé contra
  `nvidia-x11/default.nix` que `production`/`stable` está en **595.84**,
  muy por encima. Y los problemas de "PRIME offload" que aparecen mucho en
  búsquedas (terminal inutilizable con `prime-run`, etc.) son específicos
  del modo *offload* -- no aplican al modo *sync* que se eligió a propósito.

## Auditoría exhaustiva #10 (2026-07-12) — validación con Nix REAL instalado, no solo revisión manual

Esta ronda cambió de método por completo: se instaló `nix` de verdad
(`pkg install nix`, soporte experimental de FreeBSD, versión 2.32.4) y se
usó un store local sin privilegios (`NIX_REMOTE="local?root=$HOME/.nix-testroot"`,
sin necesitar root ni build users) para correr `nix eval` real sobre el
flake. Esto reemplazó por primera vez la verificación manual/heurística de
las 9 rondas anteriores por evaluación real del propio Nix.

**Validado con éxito, en orden creciente de profundidad:**
1. `nix flake metadata` — los 5 inputs (nixpkgs, home-manager, noctalia,
   noctalia-greeter, zen-browser) resuelven y generan un `flake.lock` real
   (agregado al repo).
2. `config.networking.hostName` — confirma que el árbol completo de
   módulos (flake → configuration.nix → los 4 módulos → integración
   home-manager → módulos de noctalia/noctalia-greeter) se resuelve sin
   errores de import ni de sintaxis.
3. `environment.systemPackages` y `home-manager.users.ale.home.packages`
   — **se forzó la resolución de CADA nombre de paquete usado en todo el
   repo** contra el nixpkgs real. Todos resolvieron: `kleopatra`,
   `zen-beta`, `cudaPackages.cudatoolkit` (resuelve internamente a
   `cuda-merged`), `claude-code`, `appimage-run`, etc.
4. `config.assertions` — las ~1000 aserciones del sistema completo
   evaluaron `true` (lista de fallidas: `[]`).
5. `config.system.build.toplevel.drvPath` — la prueba más fuerte posible
   sin compilar binarios Linux desde FreeBSD: construye la derivación
   completa del sistema. **Se resolvió con éxito** tras corregir los bugs
   de abajo:
   `/nix/store/kmfljanxmdpr5h06q28255w22l4mfd95-nixos-system-ale-26.11.20260711.e7a3ca8.drv`

Para llegar al paso 4-5 hizo falta parchear temporalmente
`hosts/ale/hardware-configuration.nix` con un `fileSystems."/"` ficticio
(el placeholder real no tiene ninguno, lo cual por sí solo hace tropezar la
lógica interna de `nixos/modules/tasks/filesystems.nix` al construir el
*mensaje* de una aserción de detección de ciclos -- no es un bug mío, es
un efecto secundario de forzar la evaluación de mensajes de aserciones que
normalmente son perezosos). El parche se revirtió con
`git checkout -- hosts/ale/hardware-configuration.nix` en cuanto terminó la
prueba; el placeholder real no cambió.

### Bugs reales encontrados por el evaluador que la revisión manual (9 rondas) no había atrapado

- **`home/ale/home.nix`: `programs.gpg.scdaemonSettings.card-timeout = 5;`**
  — tipo incorrecto. El tipo real es `string or boolean or list of string`,
  no entero. Con esto el build entero fallaba con
  `is not of type 'string or boolean or list of string'`. Corregido a
  `card-timeout = "5";` (el texto generado en `scdaemon.conf` es idéntico).
- **`modules/desktop.nix`: `fonts.packages` tenía `noto-fonts-emoji`** —
  renombrado en nixpkgs a `noto-fonts-color-emoji`; el nombre viejo tira un
  error duro (no solo deprecation warning). Corregido.
- **`modules/desktop.nix`: `hardware.pulseaudio.enable`** — renombrado a
  `services.pulseaudio.enable` (warning de deprecación, no error duro
  todavía, pero corregido igual para no depender del alias).
- **`home/ale/home.nix`: `programs.git.userName`/`userEmail`** —
  renombrados a `programs.git.settings.user.name`/`.email` (mismo caso,
  warning por ahora). Corregido.

Ninguno de estos cuatro se podía haber atrapado sin evaluar contra el
nixpkgs real de este momento -- son renombres/cambios de tipo que
ocurrieron en algún punto de la historia de nixpkgs/home-manager después de
que yo hubiera verificado esos módulos contra el código fuente en rondas
anteriores (el código que leí en su momento coincidía con lo que escribí;
lo que cambió fue la versión de nixpkgs resuelta por el flake, que apunta a
`nixos-unstable` y por lo tanto a HEAD en movimiento).

**Conclusión práctica:** con Nix instalado en esta sesión, se puede (y
debería) seguir corriendo `nix eval`/`nix flake check` en futuras rondas en
vez de depender solo de lectura de código fuente -- es estrictamente más
confiable.

## Auditoría exhaustiva #11 (2026-07-12) — inspección de datos reales vía `nix eval --json` + `nix flake check`

Con Nix ya instalado, esta ronda volcó la **estructura de datos real** (no
solo "¿evalúa sin error?") de las tres piezas de config más delicadas para
verificar anidamiento, con `nix eval --json`:

- `security.sudo.extraRules` → `[{root,ALL},{wheel,ALL},{ale,pcscd
  NOPASSWD},{ale,tailscale NOPASSWD}]` -- confirma que `lib.mkAfter` puso
  mis reglas después de las del módulo, en el orden correcto.
- `home-manager.users.ale.programs.noctalia.settings` →
  `{"shell":{"polkit_agent":true},"theme":{"builtin":"Catppuccin","mode":"dark","source":"builtin"}}`
  -- confirma que `shell.polkit_agent = true;` (azúcar de ruta de atributo
  de Nix) generó anidamiento real, no una clave plana con punto literal.
- `services.pipewire.wireplumber.extraConfig` →
  `{"51-bluez-avrcp":{"monitor.bluez.properties":{"bluez5.dummy-avrcp-player":true}}}`
  -- confirma el uso correcto de claves de string citadas (con puntos
  literales, el formato que espera WirePlumber) en vez de azúcar de ruta.

Las tres coincidieron exactamente con lo esperado. Sin bugs nuevos, pero es
verificación real, no supuesta.

También corrí `nix flake check --no-build`: falla, pero **solo** por el
mensaje estándar y esperado de NixOS ("The 'fileSystems' option does not
specify your root file system" -- el placeholder intencional de
`hardware-configuration.nix`), no por ningún otro check adicional del
flake. Confirma que no queda nada más por descubrir con este comando en
particular hasta que el placeholder se reemplace por el real.

## Auditoría exhaustiva #12 (2026-07-13) — primera sesión en la máquina NixOS real, ya instalada

A diferencia de las rondas 1-11 (armadas en la sesión de FreeBSD, sin acceso
al hardware), esta ronda corrió **en la máquina NixOS ya instalada y en uso**
(laptop Intel+Nvidia, `nixos-rebuild switch` real). Se resolvieron los
últimos `AJUSTAR` contra hardware/software real y se encontraron varios bugs
que solo podían aparecer en uso real (errores de Hyprland en runtime,
Noctalia corriendo con temas reales, Forgejo real).

### Placeholders finales resueltos

- `hosts/ale/hardware-configuration.nix` y `system.stateVersion`/
  `home.stateVersion` (ambos en `"26.05"`) — el usuario ya los había
  reemplazado con los reales del instalador.
- `modules/graphics.nix`: `lspci -D | grep -E "VGA|3D"` dio
  `0000:00:02.0` (Intel) y `0000:01:00.0` (Nvidia) → convertidos con la
  fórmula real del módulo (`PCI:<bus>@<domain>:<device>:<function>`,
  decimal) a `PCI:0@0:2:0` / `PCI:1@0:0:0` — coincidían exactamente con el
  placeholder que ya estaba puesto (casualidad, no verificación previa).
- `hyprland.lua`: nombre de monitor `eDP-1` confirmado con `hyprctl
  monitors` real — coincidía con el placeholder, tampoco hubo que tocarlo.

### BUG real (runtime), corregido: `gestures.workspace_swipe` ya no existe

Hyprland ≥0.51 eliminó por completo el toggle clásico `gestures:
workspace_swipe` (booleano), reemplazado por un sistema de gestos nuevo.
Confirmado leyendo el stub real instalado
(`/nix/store/.../hyprland-0.55.4/share/hypr/stubs/hl.meta.lua`) y el
ejemplo oficial (`share/hypr/hyprland.lua`): la sintaxis correcta es
`hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })`.
De paso se validó el resto de `hyprland.lua` (input/general/decoration/
animations/monitor/workspace_rule/layer_rule/dispatchers) contra ese mismo
stub — todo lo demás ya era válido.

### Escala de monitor: `"auto"` resolvía a 1.5 en un panel 1080p

`hl.monitor({ scale = "auto" })` resolvía a `1.50` en el panel real
(1920x1080, 15.3", ~144 PPI) — reduce el espacio lógico a 1280x720,
causando que el dock/barra de Noctalia se viera amontonado y las ventanas
grandes. Fijado a `scale = "1"` (a pedido del usuario, tras comparar las
tres opciones).

### Integración de Noctalia: comparación contra las 3 páginas de doc oficial + el binario real

Pedido explícito de verificar contra `docs.noctalia.dev/v5/compositor-
settings/hyprland`, `.../getting-started/nixos` y `.../getting-started/
running-the-shell`. Los requisitos de nivel NixOS (`recommendedServices`,
NetworkManager, Bluetooth, power-profiles-daemon, upower) ya estaban
completos desde antes. Gaps reales encontrados en `hyprland.lua`:

- **Atajos IPC reales:** las rondas 1 y 6 habían dejado esto como
  incertidumbre explícita, comentado, con un comando inventado
  (`noctalia-shell ipc call ... toggle`). La doc oficial sí publica el
  comando real: `noctalia msg panel-toggle launcher` / `panel-toggle
  control-center` / `settings-toggle`. Ya no es una suposición.
- **Teclas multimedia** cambiadas de `wpctl`/`brightnessctl` directo a
  `noctalia msg volume-up/down/mute` y `brightness-up/down`, tal cual la
  doc, para que se vea el OSD del propio shell.
- **`layer_rule`** le faltaban `name = "noctalia"` y `no_anim = true`.
- **`window_rule`** nuevo para la ventana de ajustes de Noctalia
  (`dev.noctalia.Noctalia`, flotante, 1080×920) — no existía ninguno.
- **Binary cache de `noctalia.cachix.org`** no estaba configurado en
  ningún lado — sin esto cada rebuild que toca Noctalia la compila desde
  fuente. Agregado en `hosts/ale/configuration.nix` (`nix.settings.extra-
  substituters`/`extra-trusted-public-keys`).

### BUG real, corregido: Noctalia no puede auto-inyectar su theme en Hyprland porque `hyprland.lua` es un symlink de solo lectura

Noctalia genera archivos de color por template
(`~/.config/{gtk-3.0,gtk-4.0}/noctalia.css`, `~/.config/hypr/noctalia.lua`,
etc.) y normalmente los auto-instala en la app destino escribiendo directo
sobre su config -- para Hyprland, su propio
`assets/templates/hyprland/apply.sh` intenta *agregar* la línea
`require("noctalia").apply_theme()` al final de `hyprland.lua`. Como acá
`~/.config/hypr/hyprland.lua` es un symlink de solo lectura al store de Nix
(gestionado por home-manager), esa escritura falla en silencio -- los
bordes de ventana nunca tomaban el color de Noctalia pese a que
`~/.config/hypr/noctalia.lua` sí se generaba correcto. Solución: se agregó
el mismo `require("noctalia").apply_theme()` a mano en el `hyprland.lua`
del repo, envuelto en `pcall` (en una instalación nueva, ese archivo no
existe todavía en el primer arranque, antes de que Noctalia corra por
primera vez -- sin el `pcall`, Hyprland fallaría al parsear el resto del
archivo ese primer boot).

GTK (`gtk.css` ya traía `@import "noctalia.css"` con las variables
`@define-color` correctas de libadwaita) y kitty (`kitty.conf` ya tenía el
`include themes/noctalia.conf`) **no tenían este problema** porque esos
archivos no están gestionados por home-manager -- Noctalia sí pudo
escribirlos directo. El patrón general: cualquier app cuya config SÍ esté
declarada vía Nix/home-manager como `xdg.configFile`/símlink corre este
mismo riesgo; el resto no.

### BUG real, corregido: falta `python3` para el template `kcolorscheme` (Kleopatra)

El template `kcolorscheme` (categoría KDE) depende de un script Python
(`assets/templates/kde/apply.py`) que fusiona el color-scheme generado
dentro de `~/.config/kdeglobals`. Sin `python3` instalado, el script no
corre y Kleopatra nunca hereda el tema. Agregado `python3` a
`environment.systemPackages`.

### Gestor de archivos: no hay ninguno "recomendado por Noctalia"

El propio README de Noctalia dice explícito que la gestión de archivos
está fuera de su alcance ("belong to the compositor, dedicated desktop
applications, or system services"). Verificado con `noctalia theme
--list-templates` (binario real instalado): el único gestor de archivos
con *template de color oficial* es `yazi` (TUI, categoría community, no
built-in). A pedido del usuario se instalaron **Nautilus** (GTK4, hereda
color solo vía el template built-in `gtk4`) y **yazi** (`theme.templates.
community_ids = [ "yazi" ]`), más `services.gvfs.enable = true` (sin esto
Nautilus no tiene papelera ni monta MTP/removibles/redes -- confirmado que
es un `mkEnableOption` con default `false`).

Nota aparte encontrada en runtime: el `community_ids` declarado vía Nix
escribe `~/.config/noctalia/config.toml` correctamente, pero Noctalia
**prioriza su propio estado runtime** (`~/.local/state/noctalia/
settings.toml`, editable desde el menú de ajustes) sobre ese archivo para
cualquier clave ya presente ahí -- confirmado leyendo el módulo real de
home-manager (`nix/home-module.nix`: *"these settings can still be
overwritten at runtime via the settings menu"*). Reiniciar el proceso de
Noctalia no re-sincroniza solo; hace falta tocar el estado directamente o
usar el menú de ajustes.

### Theme + wallpapers: cambio a Gruvbox

A pedido del usuario, cambiado `theme.builtin` de `"Catppuccin"` a
`"Gruvbox"` (confirmado como valor válido del enum real en `example.toml`).
Wallpapers instalados como **paquete Nix real** (no archivos sueltos por
curl): input de flake `github:AngelJumbo/gruvbox-wallpapers` (tiene su
propio `flake.nix`, expone paquetes por categoría), categoría `default`
(554 imágenes, ~1.4GB, confirmado con la API de GitHub antes de agregarlo)
instalada vía `home.file."Pictures/Wallpapers/gruvbox"` con
`recursive = true`, siguiendo exactamente el patrón que documenta el
README de ese repo para Home Manager. `programs.noctalia.settings.
wallpaper.directory` apuntado ahí (antes vacío, `""`, sin configurar).
Nota de procedencia: el propio README del repo de wallpapers dice que son
contribuciones de comunidad sin licencia formal y con fuente no siempre
rastreada -- aceptable para uso personal, no para redistribuir.

### YubiKey / GPG / SSH: verificado de punta a punta en la máquina real

- **SSH ya funcionaba solo** (`ssh-add -L` devuelve la llave de
  autenticación de la card) gracias a `services.gpg-agent.
  enableSshSupport = true`, ya configurado desde las rondas de FreeBSD.
  No hizo falta ningún cambio.
- **BUG real en el README, corregido:** el comando de import de GPG
  combinaba `--recv-keys --fetch-key <url>` en una sola invocación -- gpg
  trata cada uno como un "comando" independiente y son incompatibles entre
  sí (`gpg: órdenes incompatibles`). Corregido a solo `--fetch-key <url>`.
  El paso de `trust` (interactivo por naturaleza: pide nivel 1-5 +
  confirmación) se volvió no-interactivo con
  `echo -e "5\ny\n" | gpg --no-tty --command-fd 0 --edit-key <id> trust quit`.
  Verificado con un commit de prueba real: `git commit -S` +
  `git log --show-signature` mostró `Firma correcta`.
- **BUG real, corregido: email de git no coincidía con el UID de la llave
  GPG.** `programs.git.settings.user.email` estaba en
  `anything.la@tuta.com`, pero la llave GPG tiene UID `ale_bnes@tuta.com`
  (visible en "Login data" de `gpg --card-status` y en el certificado
  importado). Forgejo verificaba la firma como criptográficamente válida
  pero marcaba el commit como *"Firmado por un usuario no fiable que no
  coincide con el colaborador"* porque el email no matcheaba ningún email
  verificado de la cuenta. Corregido el email; a pedido del usuario **no**
  se reescribió el commit ya pusheado con el email viejo (queda con la
  advertencia, inofensivo, la firma sigue siendo válida).

### Infraestructura del repo (no config de NixOS, pero bloqueaba todo lo anterior)

- Todo `/nixdots` (incluido `.git`) era propiedad de `root`, no de `ale` --
  bloqueaba tanto mis ediciones directas (tuve que copiar a un scratchpad y
  dar comandos `sudo cp` uno por uno) como los `git add`/`commit` del
  usuario (ni siquiera podía crear `.git/index.lock`). Resuelto con
  `sudo chown -R ale:users /nixdots` a pedido explícito del usuario --
  desde ese punto las ediciones ya no necesitaron el baile de sudo.
- `git` tiraba "posesión dudosa" (`dubious ownership`) por el mismo motivo;
  como `~/.config/git/config` es un symlink de solo lectura de
  home-manager, `git config --global` no servía -- se resolvió con
  `sudo git config --system --add safe.directory /nixdots` (escribe en
  `/etc/gitconfig`, no gestionado por home-manager).
- `origin` apuntaba al espejo de GitHub (HTTPS, pide usuario/contraseña en
  vez de usar la YubiKey). El repo real es un Forgejo self-hosted,
  accesible vía Tailscale por SSH
  (`ssh://git@pcale.tail32b955.ts.net:2222/Ale/Nix-Dotfiles.git`, puerto
  2222) -- el espejo de GitHub lo actualiza el propio Forgejo, no hace
  falta pushear ahí a mano. Renombrado `origin` → repo real, eliminado el
  remote del espejo. Host key de `pcale` verificada con el usuario antes
  de agregarla a `known_hosts` (primera conexión, sin entrada previa).

## Auditoría exhaustiva #13 (2026-07-13) — LibrePods en uso real: audio, theming Qt, shell

Con LibrePods ya compilado y usándose de verdad (AirPods conectados,
reproduciendo audio, firmando commits), aparecieron varios problemas que
solo salen a la luz con uso real, no con una instalación limpia.

### Audio Bluetooth cortado -- diagnosticado en vivo, parcialmente resuelto

El usuario reportó audio cortado en los AirPods. Descartado metódicamente,
en este orden:

1. **No era LibrePods forzando el códec**: aun matando el proceso, seguía
   cortado -- el códec activo (`api.bluez5.codec`) seguía en `sbc_xq`
   porque WirePlumber recuerda el último perfil negociado por dispositivo,
   independiente de si LibrePods corre o no.
2. **No era contienda con otro dispositivo**: el celular seguía emparejado
   y conectado a los mismos AirPods a la vez -- se descartó apagando su
   Bluetooth y probando de nuevo, sin cambio.
3. **No eran los AirPods ni el entorno**: prueba de control clave, los
   mismos AirPods sonando perfecto conectados directo al celular.
4. **No eran xruns de PipeWire ni pérdida de paquetes Bluetooth**: `pw-top`
   en vivo mientras sonaba cortado mostró `ERR: 0` y CPU en microsegundos;
   una captura de 15s con `sudo btmon` durante el corte no mostró errores,
   desconexiones ni retransmisiones a nivel HCI -- 70,065 líneas de tráfico
   normal.
5. **Sí era el códec `sbc_xq`**: forzado a mano con `wpctl set-profile` a
   `a2dp-sink-sbc` (SBC normal), el audio quedó limpio al toque. Confirmado
   con el usuario en vivo.

**Fix aplicado:** `bluez5.codecs` (propiedad real de PipeWire, confirmada
contra `pipewire-props(7)`: *"Enabled A2DP codecs (default: all)"*) puesto
en `modules/desktop.nix` bajo `monitor.bluez.properties`, restringido a
`["sbc"]` inicialmente -- más robusto que parchear la preferencia
hardcodeada de LibrePods (`media_controller.rs` prueba `sbc_xq` primero
siempre), porque ninguna app puede negociar un códec que ni se ofrece.

**Sin resolver del todo:** tras un rato de uso sostenido, el audio con SBC
normal también empezó a fallar, se recuperó tras una pausa de ~2 minutos,
y volvió a fallar. Mismo patrón probando con `aac` agregado a la lista
(`["sbc" "aac"]`, todavía en el repo para comparar). Como esto pasa con
ambos códecs y ninguna herramienta de diagnóstico (PipeWire, HCI) mostró
error alguno, la hipótesis actual es **throttling térmico** del adaptador
Bluetooth/WiFi combo (Intel AC9560, comparte antena) bajo uso sostenido --
pendiente de confirmar revisando temperatura de la zona de la antena y si
el ventilador mantiene RPM normal durante la degradación. No es un
problema de configuración de NixOS hasta donde se pudo diagnosticar esta
ronda.

### BUG real, corregido: Kleopatra y pinentry-qt no mostraban el theme de Noctalia

`~/.config/kdeglobals` ya tenía los colores correctos de Gruvbox/Noctalia
(confirmado con un `cat` real, incluyendo secciones `[Colors:Window]` /
`[Colors:View]` con los RGB esperados) -- el template `kcolorscheme`
(arreglado en la ronda #12 agregando `python3`) sí estaba funcionando. Pero
ni Kleopatra ni el diálogo de `pinentry-qt` (PIN de la YubiKey) mostraban
esos colores, ni reabriendo las apps. Causa real: faltaba el **plugin de
QPA platform theme** que aplica `kdeglobals` a cualquier app Qt --
`kdePackages.plasma-integration` (provee `KDEPlasmaPlatformTheme6.so`) +
`kdePackages.breeze` (el estilo Qt que renderiza esa paleta) +
`QT_QPA_PLATFORMTHEME = "kde"` (`environment.sessionVariables`). Sin el
plugin, tener los datos correctos en `kdeglobals` no servía de nada --
ninguna app Qt sabía de dónde sacar la paleta.

Nota de infraestructura: como `QT_QPA_PLATFORMTHEME` es una variable de
sesión, `gpg-agent` (corriendo desde el arranque, 17h antes del cambio) no
la había heredado -- hubo que refrescarla en caliente con
`systemctl --user set-environment QT_QPA_PLATFORMTHEME=kde` +
`gpgconf --kill/--launch gpg-agent` para probarlo sin cerrar sesión. La
variable ya se carga sola en cualquier sesión nueva gracias al fix en Nix.

### Oh My Zsh + Powerlevel10k

A pedido del usuario, se agregó `programs.zsh.oh-my-zsh` (plugins `git` +
`sudo`). Primer intento: dejar `theme` vacío asumiendo que caería al
default de oh-my-zsh (`robbyrussell`) -- **incorrecto**, confirmado
leyendo `oh-my-zsh.sh` real: el script solo carga un theme
`if [[ -n "$ZSH_THEME" ]]`, sin ningún fallback interno. El "default"
`robbyrussell` en realidad viene de la plantilla del instalador manual
(`curl | sh`), que el módulo de home-manager no usa -- resultado real:
ningún theme cargaba, prompt plano de zsh. Corregido declarando
`theme = "robbyrussell"` explícito primero, y después reemplazado del todo
por **Powerlevel10k** (a pedido del usuario, quería los bloques de color
sólidos + el wizard interactivo de `p10k configure`):

- `pkgs.zsh-powerlevel10k` + `pkgs.gitstatus` (da el binario `gitstatusd`
  -- sin él en PATH, el plugin de git status de p10k intentaría bajarlo en
  runtime, lo cual falla sin red en un sandbox de Nix) + `pkgs.meslo-lgs-nf`
  (fuente que p10k recomienda para sus glifos).
- Sourcing manual en `initContent` (no vía `oh-my-zsh.theme`, que se dejó
  vacío) ordenado después de oh-my-zsh para pisar cualquier prompt que
  hubiera puesto.
- El wizard `p10k configure` generó `~/.p10k.zsh`, pero **no pudo agregar
  la línea `source ~/.p10k.zsh` a `~/.zshrc`** (mismo problema de siempre:
  symlink de solo lectura de home-manager) -- el propio wizard lo detectó
  y avisó, eligiendo "n" (no intentarlo) en vez de fallar. El archivo
  generado se copió al repo (`home/ale/p10k.zsh`) y se declaró vía
  `home.file`, con el `source` agregado a mano en `initContent`. Si se
  vuelve a correr `p10k configure` en el futuro, hay que repetir esa
  copia manual -- el wizard nunca va a poder escribir solo.

### BUG real, corregido: cursor con el logo de Hyprland en vez de un theme

Sin ningún `home.pointerCursor` declarado, Hyprland cae a su cursor propio
por defecto (literalmente el logo de Hyprland) -- no hay theme de cursor
instalado en el sistema. Corregido con el módulo real de home-manager
(`modules/config/home-cursor.nix`): `pkgs.bibata-cursors`
(`Bibata-Modern-Amber`, tonos cálidos que combinan con Gruvbox),
`hyprcursor.enable = true` (exporta `HYPRCURSOR_THEME`/`HYPRCURSOR_SIZE`,
única forma real de que Hyprland deje de usar su fallback) y
`gtk.enable = true` (para que Nautilus/Kleopatra usen el mismo cursor).
Verificado contra el módulo real que `gtk.enable` de home-manager (el
top-level, necesario para que el cursor de GTK se aplique) solo gestiona
`gtk-3.0/settings.ini` y NO `gtk.css` a menos que se declare
`gtk.gtk3.extraCss` (que no hacemos) -- no hay conflicto con el `gtk.css`
que Noctalia ya escribe en runtime para el color del theme.

Como `HYPRCURSOR_THEME`/`HYPRCURSOR_SIZE` las lee el propio compositor al
arrancar (no una app individual), este fix necesita cerrar sesión/reiniciar
para verse -- no se puede probar en caliente como el de `QT_QPA_PLATFORMTHEME`.

### Nota de infraestructura repetida: archivos nuevos sin `git add`

Pasó de nuevo esta ronda (ya había pasado con `pkgs/librepods.nix`): un
archivo nuevo (`home/ale/p10k.zsh`) sin `git add` es invisible para Nix al
evaluar el flake vía `git+file` (`error: Path '...' is not tracked by
Git`) -- hay que agregarlo al índice de git (no hace falta commitear)
antes de que `nixos-rebuild build/switch` lo pueda ver. Vale la pena
recordar este patrón para la próxima vez que se agregue un archivo nuevo,
en vez de sorprenderse de nuevo con el mismo error.

## Referencias usadas

- https://docs.noctalia.dev/v5/getting-started/nixos/
- https://docs.noctalia.dev/v5/compositor-settings/hyprland/
- https://github.com/noctalia-dev/noctalia (código fuente: `src/auth`,
  `src/idle`, `src/shell/lockscreen`, `src/shell/polkit`, `src/i18n`,
  `nix/package.nix`, `example.toml`)
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
- https://docs.noctalia.dev/v5/getting-started/running-the-shell/
- Stub Lua real instalado (`hyprland-0.55.4/share/hypr/stubs/hl.meta.lua` y
  `share/hypr/hyprland.lua`) — usado para validar `hl.gesture`/`hl.config`/
  `hl.window_rule`/`hl.layer_rule` contra el schema real, no la doc resumida.
- Binario `noctalia` real instalado (`noctalia theme --list-templates`,
  `noctalia config validate`, `noctalia msg status`, `noctalia msg
  templates-apply`) y `assets/templates/{hyprland,kde}/apply.sh|apply.py`
  del código fuente de `noctalia-dev/noctalia` — para entender el mecanismo
  real de auto-instalación de temas por template, no solo la doc.
- https://github.com/AngelJumbo/gruvbox-wallpapers (wallpapers Gruvbox,
  paquete Nix con flake propio)
- https://forum.hypr.land/t/new-gesture-rework-0-51/824 y
  https://linuxiac.com/hyprland-0-51-released-with-reworked-gestures-new-options/
  (contexto del rework de gestos en Hyprland 0.51)
- `pipewire-props(7)` real (`pipewire-1.6.7-doc` en el store) — propiedad
  `bluez5.codecs` confirmada ahí, no de memoria.
- `kavishdevar/librepods` código fuente (`src/media_controller.rs`,
  función `get_preferred_a2dp_profile`) — confirma el orden hardcodeado de
  preferencia de códec (`sbc_xq` primero).
- Módulos reales de home-manager: `modules/config/home-cursor.nix`
  (`home.pointerCursor`), `modules/misc/gtk/gtk3.nix` (confirma que
  `gtk.enable` no toca `gtk.css` salvo `extraCss`), `modules/programs/zsh/
  plugins/oh-my-zsh.nix`, y `share/oh-my-zsh/oh-my-zsh.sh` real instalado
  (confirma que no hay fallback a "robbyrussell" sin `ZSH_THEME` seteado).
