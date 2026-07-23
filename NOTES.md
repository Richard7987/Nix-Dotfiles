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

## Reproductor de música: Feishin → Psysonic, y completado de terminal (2026-07-13)

### Feishin → Psysonic

A pedido del usuario, reemplazado `feishin` (paquete de nixpkgs) por
[Psysonic](https://github.com/Psychotoxical/psysonic) en
`environment.systemPackages` (`modules/desktop.nix`) — cliente de música
self-hosted (Navidrome) igual que Feishin, pero Tauri (React+Rust) en vez de
Electron. Verificado contra el repo real (no de memoria): tiene su propio
`flake.nix` (no está en nixpkgs), expone `packages.<system>.default`.
Agregado como input de flake (`flake.nix`, mismo patrón que `zen-browser`:
`inputs.nixpkgs.follows = "nixpkgs"`), y referenciado en `desktop.nix` como
`inputs.psysonic.packages.${pkgs.stdenv.hostPlatform.system}.default`.
Verificado con `nix eval` que `psysonic` aparece en `environment.
systemPackages` en lugar de `feishin`, y que `config.assertions` sigue en
`[]`. `~/.config/feishin` (config vieja) borrado a pedido del usuario.
**Pendiente manual:** correr `sudo nixos-rebuild switch --flake /nixdots#ale`
para aplicar (no lo corrí yo, ver política de acciones de sistema).

### fzf-tab + zsh-autosuggestions

A pedido del usuario ("sugerencias de completado" en la terminal): agregado
menú interactivo con fuzzy-search en Tab (`zsh-fzf-tab`) y autosugerencias
tipo fish desde el historial (`zsh-autosuggestions`), en `home/ale/home.nix`.

- **Riesgo real evitado, no un bug ya cometido:** iba a usar la opción nativa
  `programs.zsh.autosuggestion.enable`, pero leyendo el código fuente real de
  home-manager (`modules/programs/zsh/default.nix`, rev
  `7566825d4652a1b885bd4ce65bd9e8def432fec9`) confirmé que esa opción fija su
  propio `lib.mkOrder 700` para el `source` de zsh-autosuggestions — que
  carga ANTES del `compinit` de oh-my-zsh (`mkOrder 800`,
  `modules/programs/zsh/plugins/oh-my-zsh.nix`) y ANTES de donde cargaría
  `fzf-tab` vía el mecanismo genérico `programs.zsh.plugins` (`mkOrder 900`,
  `modules/programs/zsh/plugins/default.nix`). Confirmé contra el README real
  de `Aloxaf/fzf-tab` (no de memoria) que el orden exigido es exactamente el
  opuesto: *"fzf-tab needs to be loaded after compinit, but before plugins
  which will wrap widgets, such as zsh-autosuggestions"*. Con la opción
  nativa, el orden real habría sido autosuggestions(700) → compinit(800) →
  fzf-tab(900) — al revés dos veces.
- **Solución:** `fzf-tab` vía `programs.zsh.plugins` (carga a 900, después
  del compinit de oh-my-zsh a 800 — correcto solo). `zsh-autosuggestions`
  sourceado a mano dentro de `initContent` envuelto en `lib.mkOrder 950`
  (en vez de la opción nativa), para que quede después de fzf-tab. Verificado
  con `nix eval` el `.zshrc` generado completo: el orden real es
  `compinit(800) → fzf-tab(900) → autosuggestions(950) → resto(1000, p10k/
  yubico/pfetch, sin envolver, como ya estaba)` — exactamente el exigido.
- Agregado `pkgs.fzf` a `home.packages` (binario que `fzf-tab` invoca para
  el menú; no era necesario antes porque nada lo requería).
- Requirió agregar `lib` a la firma de `home.nix` (`{ config, pkgs, inputs,
  ... }` no lo traía) para poder usar `lib.mkMerge`/`lib.mkOrder` en
  `initContent`.
- Paquetes `zsh-fzf-tab` y `zsh-autosuggestions` confirmados como atributos
  reales de nixpkgs (`nix build` real, no solo `nix eval` del outPath) antes
  de usarlos, y sus rutas de archivo `.plugin.zsh` confirmadas listando el
  store path ya construido, no asumidas por convención de nombre.

## zsh-syntax-highlighting (2026-07-13)

A pedido del usuario ("colores en la terminal, comandos que existen de un
color y los que no de otro" -- exactamente lo que hace `zsh-syntax-
highlighting`, la herramienta estándar para esto). A diferencia de
`autosuggestion.enable` (ver sección anterior), la opción nativa
`programs.zsh.syntaxHighlighting.enable` **sí** sourcea en el orden correcto
por defecto: confirmado en `modules/programs/zsh/default.nix` que usa
`lib.mkOrder 1200`, que cae después de `fzf-tab` (900) sin necesitar ningún
`mkOrder` manual -- satisface igual el requisito del README de fzf-tab
("before plugins which will wrap widgets"). Verificado con `nix eval` el
`.zshrc` generado: orden real `compinit(31) → fzf-tab(35) →
autosuggestions(61) → zsh-syntax-highlighting(103)`. `config.assertions`
sigue en `[]`.

## Reproductor de música: Feishin → Psysonic, caché binario y completado de terminal -- resumen de cambios previos

Ver secciones de arriba para el detalle completo: reemplazo de Feishin por
Psysonic (input de flake propio + `psysonic.cachix.org` agregado en
`hosts/ale/configuration.nix` tras el primer switch sin caché, que tardó
~23 min compilando npm+Rust/Tauri desde cero), y fzf-tab + zsh-
autosuggestions (con el bug de orden evitado, ver arriba). Todo aplicado con
éxito en la máquina real (`nixos-rebuild switch` confirmado por el usuario:
`Done.`, sin errores).

## Revisión de logs del sistema: Bluetooth (diagnosticado, no accionable) + segfault de noctalia-greeter en cada arranque + carpetas XDG (2026-07-16)

### Auditoría de `journalctl` (a pedido del usuario: "revisa los logs a ver cualquier error")

Revisados `journalctl -p 3 -xb`, `--failed` (sistema y usuario), OOM,
filesystem/disco, y `coredumpctl list` de los últimos 3 arranques. Sin
servicios systemd fallidos, sin OOM kills reales (el ciclo "OOM killer
disabled/enabled" es de suspend/hibernate, no de memoria agotada), sin
errores de disco (`ata5: SATA link down` es un puerto SATA vacío, benigno).
Dos hallazgos reales:

**Bluetooth — diagnosticado, sin fix de config posible.** Tres mensajes
repetidos en cada arranque/resume:

- `BAP requires ISO Socket which is not enabled` — el adaptador de esta
  máquina (Intel AC9560, integrado con el WiFi) es de 2018, anterior a
  Bluetooth 5.2. LE Audio/canales ISO (lo que necesita el perfil BAP) es una
  limitación de firmware/hardware del controlador, no algo que un flag de
  NixOS o de `bluetoothd` pueda habilitar. No es efecto del flag `-E`
  (experimental) que ya tenemos por LibrePods (ver más arriba, "LibrePods
  (AirPods)") — BlueZ prueba el perfil BAP en la inicialización del adaptador
  sin importar `-E`.
- `Unable to get Hands-Free Voice gateway SDP record: Host is down` y
  `a2dp-sink profile connect failed for 14:28:76:C3:CF:FF: Protocol not
  available` — confirmado con `bluetoothctl info 14:28:76:C3:CF:FF` que es
  el MAC de los AirPods Pro del usuario (`Paired: yes`, `Bonded: yes`,
  `Connected: no` en el momento de la revisión). Es `bluetoothd`
  reintentando reconectar a un dispositivo emparejado que está apagado o
  fuera de rango -- comportamiento esperado, no un bug. Búsqueda en
  `github.com/bluez/bluez/issues` encontró issues con el mismo texto exacto
  (#348, #351, #1309, #1610) pero sin resolución clara documentada en los
  hilos -- no hay parche conocido que aplicar, y dado que
  `bluez5.codecs`/el flag `-E` en `modules/desktop.nix` son el resultado de
  13 rondas de diagnóstico en vivo (ronda #13, audio cortado con los
  AirPods), **decidido no tocar esa config a ciegas** sin evidencia de que
  el cambio resuelva algo real -- el riesgo de re-romper el audio ya
  estabilizado supera el beneficio de silenciar un log.

**noctalia-greeter: segfault en el compositor al salir, en el 100% de los
arranques registrados.** Encontrado en `journalctl -k` (`noctalia-greete[PID]:
segfault ... in libwlroots-0.20.so`) y confirmado con `coredumpctl list`
(4/4 arranques con coredump, mismo binario:
`noctalia-greeter-compositor`, señal SIGSEGV). Contexto exacto del crash
(`journalctl -b -1`, alrededor del segfault):

```
[info] session start confirmed, exiting greeter
[info] shutdown complete
kernel: noctalia-greete[PID]: segfault at ... in libwlroots-0.20.so
```

El crash pasa **después** de que el greeter ya reportó `shutdown complete`
y entregó la sesión a Hyprland -- es un segfault en la limpieza/destructores
del proceso ya terminado, no algo que bloquee el login (por eso nunca se
notó "a simple vista"). Sin backtrace legible (`coredumpctl` reporta
`COREFILE inaccessible`, sin símbolos de debug en el store).

Revisado el historial real de `github.com/noctalia-dev/noctalia-greeter`:
el pin en `flake.lock` (`fffc583a`, 12 jul) estaba un día atrasado respecto
a `main` (`b0735981`, 13 jul). Ningún commit en el medio menciona
explícitamente "segfault"/"crash"/"SIGSEGV" (el más cercano,
`fix(compositor): prevent layout operations during shutdown`, es de antes
del pin actual, así que ya estaba incluido y no evitó el crash). Tampoco
hay issues abiertos con "segfault" en el tracker del proyecto. **No hay
fix confirmado upstream** -- la actualización del input
(`nix flake lock --update-input noctalia-greeter`) se hizo como intento
razonable (trae 4 commits nuevos, incluye fixes de compositor/input), no
como solución verificada.

Build validado con `nix build .#nixosConfigurations.ale.config.system.build.toplevel`
(sin sudo) antes de aplicar. Aplicado con
`sudo nixos-rebuild switch --flake /nixdots#ale` (corrido por el usuario,
`Done.` sin errores) -- pero `greetd.service` **no se reinició** (systemd
lo excluye de los reinicios en caliente de un `switch`, para no cortar la
sesión gráfica activa), así que el binario nuevo de `noctalia-greeter`
recién se usa en el próximo arranque real. **Pendiente: confirmar tras un
reinicio real si el segfault sigue apareciendo** (`coredumpctl
list --since=today` después de reiniciar). Si sigue, hace falta reportarlo
upstream con un backtrace real (requeriría un build con símbolos de debug,
no intentado todavía).

### Carpetas XDG estándar

A pedido del usuario ("solo tengo Pictures y Downloads, no recuerdo qué
más"): agregado `xdg.userDirs` en `home/ale/home.nix` (antes no estaba
declarado -- las carpetas que existían se habían creado a mano, sin pasar
por `xdg-user-dirs-update` ni estar en el repo). Nombres en inglés a
propósito (`Desktop`/`Documents`/`Music`/etc., no `Escritorio`/`Documentos`)
para no generar carpetas duplicadas junto a las `Pictures`/`Videos`/
`Downloads` en inglés que ya existían con contenido real, a pesar de que el
locale de la máquina es `es_MX.UTF-8`.

De paso se destapó una carpeta `Descargas` (con "s", duplicado en español,
vacía) que ya no existe al momento de aplicar el cambio -- el usuario debe
haberla borrado por su cuenta entre la revisión de logs y este cambio; no
hizo falta lidiar con un merge de contenido.

Tras aplicar (`nixos-rebuild switch`, confirmado por el usuario), se generó
`~/.config/user-dirs.dirs` con las 8 carpetas declaradas, más una
`XDG_PROJECTS_DIR="/home/ale/Projects"` que **no** se declaró en este
cambio -- viene de algún módulo ya importado (`inputs.noctalia.homeModules.
default` es sospechoso, no confirmado con `nix eval` cuál exactamente).
Documentado acá para no sorprenderse de nuevo si aparece en otro contexto.

## got (Game of Trees) (2026-07-16)

A pedido del usuario: agregado `got` (`pkgs.got`, confirmado real contra
nixpkgs con `nix eval nixpkgs#got.pname/.version` antes de agregarlo --
versión 0.126) a `environment.systemPackages` en `modules/desktop.nix`, como
alternativa opcional a `git` para el mismo repo.

### Investigación previa a agregarlo (a pedido del usuario, antes de tocar código)

Contra el manual real de `gameoftrees.org` (`got.1`, `got.conf.5`), no de
memoria:

- **Compatibilidad de repo:** `got` opera sobre el mismo formato de repo
  Git "bare" en disco -- no migra ni convierte nada, `git` y `got` pueden
  coexistir sobre el mismo repo sin pisarse.
- **SSH:** `got clone`/`fetch`/`send` soportan `ssh://usuario@host`
  invocando `ssh(1)` del sistema (con `ssh-agent`), igual que `git` -- la
  autenticación SSH ya configurada vía `gpg-agent` + YubiKey
  (`services.gpg-agent.enableSshSupport`, ver sección YubiKey/GPG) no
  cambia en nada.
- **Firma:** `got commit` **no tiene ninguna opción de firma** (ni GPG ni
  SSH) -- confirmado en el synopsis real (`[-CNnS]`, la `-S` ahí es para
  symlinks fuera del árbol versionado, no para firmar). Solo `got tag -S`
  firma, y únicamente con firma **SSH** (`ssh-keygen -Y sign`/`ssh-agent`),
  nunca GPG. Como el repo ya tiene commits firmados con GPG vía la YubiKey
  (verificados con `git log --show-signature`, ver sección YubiKey/GPG),
  la conclusión fue: **no reemplazar `git commit -S` por `got commit`** --
  ambas herramientas conviven sobre el mismo repo, se puede seguir
  commiteando y firmando con `git` y usar `got` para lo demás (log, status,
  diff, fetch/send) si se prefiere su UX.

### `got checkout` requiere un *work tree* propio y vacío -- no funciona "en el lugar"

Verificado en vivo (no solo con el manual, que en un resumen automático
inicial sugería incorrectamente que existía una opción `-f` para forzar el
checkout dentro de un directorio no vacío -- **no existe tal opción en la
0.126 real**, confirmado con el `usage:` real del binario:
`checkout [-Eq] [-b branch] [-c commit] [-p path-prefix] repository-path
[work-tree-path]`, sin `-f`). Un *work tree* de `got` es una estructura
propia (metadata en `.got/`: `base-commit`, `file-index`, `head-ref`,
`repository`, `uuid`) completamente distinta del checkout que deja
`git clone` -- **no se puede simplemente empezar a correr `got status`/
`got commit` adentro de `/nixdots`** (que ya tiene `.git/` + archivos de
`git clone`), porque `got checkout` exige que `work-tree-path` esté vacío.

Probado en un repo descartable en el scratchpad antes de intentar nada
contra el repo real, justamente para no arriesgar los cambios sin
commitear que ya había en `/nixdots` (`home/ale/hyprland.lua`, un cambio
del usuario ajeno a esta tarea) -- confirmó el error `invalid option -- 'f'`
en vez de asumir el comportamiento de memoria/de un resumen de doc.

### Flujo real para probar `got commit`/`got send` una vez sobre este repo

Dado lo anterior, para commitear con `got` hace falta un *work tree*
separado (reutiliza los mismos objetos de `/nixdots/.git`, así que no
duplica historia ni diverge):

```sh
got checkout -b main /nixdots/.git ~/nixdots-got   # work-tree-path debe estar vacío/no existir
cp /nixdots/modules/desktop.nix ~/nixdots-got/modules/desktop.nix
cp /nixdots/README.md /nixdots/NOTES.md ~/nixdots-got/
cd ~/nixdots-got
got status
got commit -m "..."
got send ssh://git@pcale.tail32b955.ts.net:2222/Ale/Nix-Dotfiles.git
```

Tras el `got send`, hace falta sincronizar `/nixdots` (el checkout de
`git` real que usa `nixos-rebuild --flake /nixdots#ale`) de vuelta, sin
tocar el cambio ajeno pendiente en `hyprland.lua`:

```sh
cd /nixdots
git fetch origin
git checkout origin/main -- modules/desktop.nix README.md NOTES.md  # objetivo, no toca hyprland.lua
git merge --ff-only origin/main
```

**Remoto real confirmado** (`git remote -v` en `/nixdots`): `origin` es
`ssh://git@pcale.tail32b955.ts.net:2222/Ale/Nix-Dotfiles.git` -- un
servidor Git propio expuesto por Tailscale (puerto 2222), **no
github.com directo** (a pesar de que la primera pregunta del usuario sobre
`got` hablaba de "push a GitHub"). No debería ser un problema real: el
esquema `ssh://` de `got` implementa el mismo protocolo de empaquetado de
Git (`git-upload-pack`/`git-receive-pack`) que usa cualquier cliente Git
por SSH, no algo exclusivo de GitHub -- cualquier servidor Git estándar
(Gitea/Forgejo/gitolite/etc.) debería aceptarlo igual.

**Primer intento, falló -- pero la causa real NO fue el servidor.**
`got send`/`got fetch` con la URL completa
(`ssh://git@pcale.tail32b955.ts.net:2222/Ale/Nix-Dotfiles.git`) como
argumento posicional devolvían `remote repository not found` en los dos.
La hipótesis inicial (protocolo Git v2 por SSH que el servidor no
soportaría) quedó descartada al revisar los logs de Forgejo del lado del
servidor (sesión de Claude Code corriendo en `pcale`, la misma máquina que
aloja Forgejo): **cero intentos de conexión SSH** de `got`, ni exitosos
ni rechazados, mientras que los dos `git push` sí quedaron registrados con
`Accepted publickey` + `git-receive-pack ... 200 OK`. Es decir, `got`
nunca llegó a marcar ni siquiera el handshake SSH -- confirma que el
problema era 100% del lado del cliente, no del servidor.

Confirmado con `strace -f -e trace=execve,connect` sobre `got fetch`:
pasando la **URL completa** como argumento, `got` corre
`got-read-gitconfig /nixdots/.git/config` y falla ahí mismo, **sin
ejecutar `ssh` ni un solo `connect()`** -- el error salta en el parseo
del argumento posicional, antes de intentar red. Pasando en cambio el
**nombre del remoto ya definido en `.git/config`** (`got fetch -v
origin`), el trace muestra a `got` resolviendo ese remoto vía
`got-read-gitconfig`, ejecutando de verdad
`/nix/store/.../openssh-10.3p1/bin/ssh -p 2222 -- git@pcale.tail32b955.ts.net
git-upload-pack '/Ale/Nix-Dotfiles.git'`, conectando por `AF_INET` a la IP
de Tailscale (`100.85.17.100:2222`), usando el socket SSH de
`gpg-agent`/YubiKey (`/run/user/1000/gnupg/S.gpg-agent.ssh`) para
autenticar, y terminando con `Already up-to-date` -- éxito completo.

**Conclusión real:** `got` sí lee los remotos de `.git/config` de `git`
(contra lo que se había dejado como "no confirmado" más arriba), pero
**no acepta una URL `ssh://` cruda como argumento posicional de la misma
forma que `git`** -- hay que pasarle el **nombre del remoto** (`origin`),
no la URL completa. El comando correcto para pushear con `got` en este
repo es `got send origin`, no `got send ssh://...`. SSH, Tailscale,
`gpg-agent`/YubiKey y el servidor Forgejo funcionan todos correctamente
con `got` -- el error de la ronda anterior era un argumento mal armado de
mi parte, no una incompatibilidad real.

**Cómo se subió el commit finalmente:** dado que el error se detectó y
corrigió después de ya haber resuelto el push con `git push` normal (el
commit de `got commit` vive en el mismo `.git` real -- `repository-path`
de `got checkout` era `/nixdots/.git` directo, no una copia -- y `got`
ya había movido `refs/heads/main` local a ese commit), no hizo falta
repetir el `got send`. Antes del `git push` hizo falta `git add` de los
3 archivos tocados para que el índice de `git` (que `got commit` no toca
-- tiene su propio índice en `.got/file-index`) dejara de mostrar diffs
falsos contra el HEAD ya movido.

## Atajo de bloqueo de pantalla, `mainMod+L` (2026-07-16)

Agregado en `home/ale/hyprland.lua` junto a los otros atajos IPC de
Noctalia (`mainMod+Space`/`+S`/`+comma`, ronda "Auditoría exhaustiva #12"):

```lua
hl.bind(mainMod .. "+L", hl.dsp.exec_cmd(noctaliaMsg .. "session lock"))
```

Mismo patrón que los atajos ya existentes (`noctalia msg <comando>` vía
`hl.dsp.exec_cmd`), `session lock` es el comando IPC real de Noctalia para
bloquear la sesión (pantalla de bloqueo propia de Noctalia, ver
`src/shell/lockscreen/` mencionado en la ronda de auditoría #12 de este
mismo archivo). Cambio autocontenido, no requiere tocar `modules/
desktop.nix` ni ningún paquete nuevo.

## weechat (2026-07-16)

Agregado a `home.packages` en `home/ale/home.nix`, junto al resto de
paquetes CLI de terminal (`fzf`, `pfetch`). Petición del usuario tal cual
("nix-shell -p weechat ... o agrégalo a tu flake de dotfiles como paquete
normal"): un cliente IRC de terminal, sin ningún componente gráfico ni de
sistema que declarar.

- **Sin módulo declarativo en home-manager.** Verificado buscando
  `weechat` en el source real del input `home-manager` (rev
  `7566825d4652a1b885bd4ce65bd9e8def432fec9`, resuelto vía
  `builtins.getFlake "path:/nixdots"` para obtener el store path exacto del
  input pineado en `flake.lock`) — no hay ningún `modules/programs/
  weechat.nix` ni mención alguna del paquete en todo el árbol. A diferencia
  de `programs.git`/`programs.zsh`, no hay opciones tipadas para
  plugins/scripts/servers de WeeChat; toda esa configuración vive dentro
  del propio WeeChat en runtime (`/script install ...`, `/server add ...`),
  no versionada en este repo. Si en el futuro se quiere declarar servers o
  scripts de forma reproducible, la vía sería `xdg.configFile` apuntando a
  `~/.config/weechat/*.conf` a mano (mismo patrón que otras apps sin
  módulo dedicado), no una opción nativa.
- **Paquete confirmado en el nixpkgs real** (mismo pin que resuelve el
  resto del repo): `pkgs.weechat.meta.description` evaluó a *"Fast, light
  and extensible chat client"` sin error.
- **Validado con `nix eval` real** (mismo método que las rondas
  #10/#11): `home-manager.users.ale.home.packages` incluye
  `weechat-bin-env` (nombre del derivation wrapper de WeeChat) tras el
  cambio, y `config.system.build.toplevel.drvPath` del sistema completo
  sigue resolviendo sin error con el paquete agregado.
- No hace falta `sudo nixos-rebuild switch` para *probar* WeeChat antes de
  aplicarlo permanentemente — `nix-shell -p weechat` (como sugirió el
  usuario) lo prueba sin tocar la config declarativa. El cambio en el repo
  es para tenerlo instalado de forma permanente sin depender de acordarse
  del `nix-shell` cada vez.

## IntelliJ IDEA Ultimate, nokkvi, y audio cortado en psysonic con álbumes hi-res (2026-07-16/17)

**IntelliJ IDEA Ultimate.** `jetbrains.idea` directo de nixpkgs en
`home.packages` (`home/ale/home.nix`), no JetBrains Toolbox — Toolbox baja
binarios fuera del store y se autoactualiza por su cuenta, no encaja con el
modelo declarativo de este repo (mismo motivo por el que LibrePods se
compila de fuente en vez de depender de un AppImage). `allowUnfree` ya
estaba en `true` a nivel sistema (`hosts/ale/configuration.nix`, por
Nvidia/Steam), `home-manager.useGlobalPkgs = true` lo hereda. Requiere
login/licencia JetBrains la primera vez que se abre.

**nokkvi** (cliente nativo de Navidrome, Rust/Iced,
github.com/f-o-o-g-s/nokkvi) — coexiste con `psysonic`, no lo reemplaza
(decisión explícita del usuario). A diferencia de LibrePods, este proyecto
sí tiene releases oficiales de Linux con binario prebuilt, pero su
`Cargo.toml` pinea `iced` a un commit de la rama `master` upstream (no
crates.io) — compilarlo con `buildRustPackage` hubiera dependido de un
`outputHashes` frágil, roto en cada bump de esa fork. Se empaquetó en
`pkgs/nokkvi.nix` bajando el binario oficial del release (`fetchurl` +
`autoPatchelfHook`), verificando el `sha256` del tarball contra el
`.sha256` que el propio proyecto publica junto a cada release. Runtime deps
confirmadas con `readelf -d` real sobre el binario (fontconfig, freetype,
alsa-lib, pipewire, y `stdenv.cc.cc.lib` para `libgcc_s.so.1`, que no la
trae ningún paquete de arriba); `vulkan-loader`/`libxkbcommon`/`wayland`
como `runtimeDependencies` porque iced/wgpu (mismo stack que LibrePods) los
resuelven vía `dlopen` en runtime, no aparecen en `readelf -d`. Build
verificado en vivo (`nix build` + `nokkvi --version`).

**Removido el mismo día** (decisión del usuario, sin razón registrada en
esta sesión) — `pkgs/nokkvi.nix` borrado y la línea sacada de
`home.packages`. Queda el detalle de empaquetado de arriba como referencia
real y ya verificada por si se reinstala más adelante (el patch de la
release/hash/runtime deps sigue siendo válido salvo que haya salido una
versión nueva).

**Audio cortado en psysonic con álbumes hi-res (FLAC 24-bit/192kHz).**
Reporte del usuario: 2 álbumes nuevos (Electric Light Orchestra "Discovery"
y otro) sonaban cortados en psysonic, pero bien con otros clientes de
Navidrome y bien con el resto de la biblioteca en el propio psysonic.
Diagnóstico en varias rondas, con dos hallazgos reales confirmados en el
camino y una causa final que terminó siendo otra:

- **Hallazgo real #1 -- `default.clock.allowed-rates` de PipeWire vacío.**
  `pw-metadata -n settings` mostraba `clock.allowed-rates=[48000]` (default
  de PipeWire sin configurar: una sola tasa fija). Los logs de psysonic
  (`psysonic --logs --tail 300`) mostraban `audio stream opened at 192000
  Hz (exact)` para los álbumes hi-res -- psysonic tiene un modo
  "bit-perfect" que intenta matchear la tasa nativa del archivo. Con el
  clock fijo, PipeWire forzaba un resample 192kHz->48kHz por atrás. Se
  agregó `services.pipewire.extraConfig.pipewire."92-clock-rates"` en
  `modules/desktop.nix` con `default.clock.allowed-rates = [ 44100 48000
  88200 96000 176400 192000 ]` -- **este cambio se mantuvo** porque sigue
  siendo correcto para el DAC hi-res real de la máquina (HiBy FC4, USB,
  confirmado con `cat /proc/asound/card1/stream0` que soporta hasta
  768kHz), más allá de que no resultó ser la causa completa del corte.
- **Hallazgo real #2 -- bug de Noctalia, stream de sonido de UI que nunca
  se desconecta.** Con `wpctl status` se vio un stream activo permanente
  llamado "Noctalia" (`node.name = noctalia-sound`, confirmado con
  `pw-dump`) compitiendo por el mismo sink (HiBy FC4) incluso horas después
  de haber sonado un solo efecto de UI (notificación, OSD de volumen).
  Revisando el código fuente real del input (`src/pipewire/
  sound_player.cpp`, `SoundPlayer::onDrained()`): marca el stream como
  `finished` pero nunca llama a `pw_stream_disconnect()` -- el
  `pw_stream_destroy()` recién corre en la PRÓXIMA vez que suena otro
  efecto (`removeFinished()`, invocado al principio de `play()`). Mientras
  ese stream siguiera conectado, PipeWire no cambiaba el clock del grafo
  para servir a otro cliente. Se armó un patch real
  (`pkgs/noctalia-sound-disconnect.patch`, con `pw_stream_disconnect()`
  agregado a `onDrained()`) y un override de `programs.noctalia.package`
  duplicado en **dos** módulos independientes (el de NixOS en
  `modules/desktop.nix` y el de home-manager en `home/ale/home.nix`, cada
  uno con su propia opción `programs.noctalia.package` -- el de
  home-manager instala en `/etc/profiles/per-user/ale/bin`, que gana en
  `$PATH` sobre `/run/current-system/sw/bin` del módulo de NixOS, así que
  hacía falta el override en los dos lados o el binario sin parchear
  ganaba igual). Patch compilado y verificado en vivo: el stream "Noctalia"
  efectivamente dejó de quedar colgado en `wpctl status` tras aplicarlo.
  **Este bug es real y sigue sin arreglar upstream** (no se reportó
  todavía), pero el patch/override se **revirtió** de este repo (borrados
  `pkgs/noctalia-sound-disconnect.patch` y `pkgs/noctalia-patched.nix`,
  sacados los dos overrides) porque no era la causa del audio cortado --
  ver siguiente punto. Si el sonido de UI colgado vuelve a molestar en el
  futuro, el patch armado acá (buscar en el historial de git de este
  archivo/repo, commit previo a la reversión) es un punto de partida real
  y ya compilado una vez.
- **Causa real.** Con los dos hallazgos de arriba aplicados, el corte
  seguía. Revisando `psysonic --logs` en el momento exacto de la
  reproducción aparecieron `[hi-res-blend] outgoing track not cached for
  blend reopen` y `[audio] ranged dl error (attempt 1/3): error decoding
  response body -- reconnecting`, ambos correlacionados con la apertura de
  streams a 192kHz. Se descartó que fuera ancho de banda/wifi (LAN directa
  por Tailscale a 13ms, sin relay DERP -- `tailscale ping` confirmó
  conexión directa; señal wifi fuerte, 79%/-41dBm/1170Mbit; `ip -s link`
  con drop rate insignificante, ~0.08%). La causa terminó siendo una
  función propia de psysonic (streaming/blend "bit-perfect" para hi-res) --
  el usuario la desactivó en la configuración de la app y el corte
  desapareció por completo. No se llegó a encontrar el toggle exacto desde
  esta sesión (el usuario lo hizo directo en la UI de psysonic) -- queda
  pendiente documentar dónde vive esa opción si hace falta tocarla de nuevo
  vía config declarativa.

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
- https://github.com/Psychotoxical/psysonic (repo real, incluido su
  `flake.nix`, verificado antes de agregarlo como input).
- https://github.com/Aloxaf/fzf-tab (README real — orden exigido de carga
  relativo a `compinit`/`zsh-autosuggestions`).
- `modules/programs/zsh/default.nix` y `modules/programs/zsh/plugins/
  default.nix` real de home-manager (rev
  `7566825d4652a1b885bd4ce65bd9e8def432fec9`) — `mkOrder` reales de
  `autosuggestion.enable` (700), compinit de oh-my-zsh (800) y
  `programs.zsh.plugins` genérico (900), que motivaron sourcear
  zsh-autosuggestions a mano en vez de con la opción nativa.
- https://github.com/noctalia-dev/noctalia-greeter/commits/main (historial
  real de commits — confirmó que el pin en `flake.lock` estaba atrasado y
  que ningún commit menciona explícitamente el segfault de salida).
- https://github.com/bluez/bluez/issues (búsqueda de "a2dp-sink profile
  connect failed" + "Protocol not available" — issues #348, #351, #1309,
  #1610, sin resolución clara documentada).
- `bluetoothctl info <MAC>` real en la máquina — confirmó que el MAC de los
  mensajes de reconexión en el log es el de los AirPods Pro del usuario,
  no un dispositivo desconocido.
- https://gameoftrees.org/got.1.html, https://gameoftrees.org/got.conf.5.html,
  https://gameoftrees.org/got-worktree.5.html — manual real de `got`
  (opciones de `checkout`/`commit`/`send`/`fetch`, formato de work tree,
  firma SSH de tags). El `usage:` real del binario 0.126 instalado
  (`got checkout -h`, etc.) se usó para corregir un resumen automático de
  doc que asumía incorrectamente una opción `-f` inexistente.
- `strace -f -e trace=execve,connect` real sobre `got fetch`/`got send` —
  confirmó que pasar la URL completa como argumento posicional nunca
  llega a ejecutar `ssh(1)` (falla antes, en el parseo), mientras que
  pasar el nombre del remoto (`origin`) sí lo hace y completa el fetch
  con éxito. Y logs de Forgejo del lado del servidor (revisados desde una
  sesión de Claude Code corriendo en `pcale`, la misma máquina que aloja
  Forgejo) — cero intentos de conexión de `got`, descartando que el
  servidor fuera la causa.

## mpv + loupe (2026-07-17)

A pedido del usuario ("agrega mpv y todas las dependencias para que pueda
reproducir cualquier tipo de video, y agrega un visor de imágenes"), agregados
ambos a `environment.systemPackages` en `modules/desktop.nix`.

- **`mpv`: no hizo falta agregar ninguna dependencia de códecs aparte.**
  Verificado leyendo el `package.nix` real de `mpv-unwrapped` y de
  `ffmpeg/generic.nix` (no de memoria, mismo método que las rondas #10/#11):
  `pkgs.mpv` enlaza `pkgs.ffmpeg`, que pese a resolver a la variante
  `"small"` (`ffmpeg_8`) tiene `withSmallDeps ? ... || withFullDeps` y
  `withHeadlessDeps ? ... || withSmallDeps` — es decir, `"small"` implica
  `withHeadlessDeps = true`, que a su vez habilita por defecto dav1d (AV1),
  libaom, libvpx (VP8/VP9), x264/x265, libbluray, vulkan, vaapi y,
  confirmado con `nix eval` real sobre `buildInputs`, **`nv-codec-headers`**
  (habilita nvdec/nvenc — decode/encode por hardware en la Nvidia real de
  esta laptop vía `--hwdec=nvdec`, sin depender de ningún shim vaapi-nvidia
  que no está instalado). El resto de contenedores/códecs (mpeg1/2/4, vc1,
  prores, theora, etc.) los trae el propio ffmpeg sin libs externas. No se
  usó `ffmpeg-full`: agrega sobre todo encoders/filtros raros irrelevantes
  para reproducir, no decoders adicionales, y alarga mucho el build.
  De paso, `nix build` mostró que `pkgs.mpv` (el wrapper, no
  `mpv-unwrapped`) arrastra `yt-dlp` solo — reproducir una URL también
  funciona sin instalar nada aparte.
- **`loupe`** — visor de imágenes GTK4/Rust (proyecto GNOME, reemplazo de
  `eog`). Elegido en vez de alternativas nativas de Wayland (`swayimg`/
  `imv`) porque hereda el theme Gruvbox/Noctalia solo, vía el mismo
  template built-in `"gtk4"` que ya usa Nautilus (confirmado que ambos
  comparten stack GTK4/libadwaita) — las alternativas de Wayland puro no
  tienen esa integración automática y requerirían theming a mano. El README
  de Noctalia no recomienda ningún visor de imágenes en particular (fuera
  de su alcance, mismo caso ya documentado para el gestor de archivos).
- Ambos paquetes confirmados reales contra el nixpkgs del flake (`nix build
  --no-link` de cada uno, resueltos desde el binary cache sin compilar) y
  validado con `nix eval` que `mpv-with-scripts`/`loupe` aparecen en
  `environment.systemPackages` del sistema completo, `config.assertions`
  sigue en `[]`, y `config.system.build.toplevel` compila sin error.
- **Pendiente manual:** correr `sudo nixos-rebuild switch --flake
  /nixdots#ale` para aplicar (no lo corrí yo, ver política de acciones de
  sistema).
- **Aplicado por el usuario, confirmado en vivo:** `which mpv loupe` resuelve
  a `/run/current-system/sw/bin/`, `mpv --version` corre real (v0.41.0).

## zola (2026-07-17)

A pedido del usuario. Encontrado ya instalado, pero de forma **imperativa**
(`nix profile list` mostró `zola` -- y de paso `nodejs`, sin tocar -- con
store path propio en `/home/ale/.local/state/nix/profiles/profile`, fuera de
este repo). Igual que con IntelliJ Toolbox/LibrePods AppImage (ver rondas
anteriores), un paquete fuera del modelo declarativo de este repo no es
reproducible por `nixos-rebuild` ni queda versionado -- movido a
`home.packages` en `home/ale/home.nix`, junto a `weechat` (mismo patrón:
herramienta CLI personal sin módulo declarativo propio en home-manager).
Confirmado con `nix eval` contra el nixpkgs pineado real de este flake
(`0.22.1`, mismo store path que ya tenía instalado) y con `nix build` del
`system.build.toplevel` completo sin errores. **No se tocó** la instalación
imperativa existente (`nix profile remove zola`) -- queda duplicada hasta que
el usuario confirme el `nixos-rebuild switch` y decida si quiere limpiarla.
**Pendiente manual:** `sudo nixos-rebuild switch --flake /nixdots#ale`.

## Migración a got puro (2026-07-22)

A pedido explícito del usuario: `/nixdots` dejó de ser un checkout de `git`
y pasó a ser un *work tree* de `got` directamente -- ya no hace falta un
work tree separado (`~/nixdots-got`) ni sincronizar de vuelta como en la
sección "got (Game of Trees)" de arriba (2026-07-16). Aceptado
explícitamente el trade-off: **los commits de este repo ya no llevan firma
GPG** (`got commit` no soporta firma, ni GPG ni SSH -- solo `got tag -S`
firma, y solo con SSH).

### Validado antes de tocar el repo real

Probado primero en un directorio descartable del scratchpad, para no
arriesgar el checkout real:

- `git clone --bare ssh://git@pcale.tail32b955.ts.net:2222/Ale/Nix-Dotfiles.git`
  deja `remote.origin.url` ya configurado en el `config` del bare repo --
  `got fetch -v origin` lo lee solo, sin necesitar `got.conf` a mano ni
  tocar nada más. Confirmado con `strace` en la ronda anterior (2026-07-16)
  que `got` ya sabía leer remotos de `.git/config`; esto confirma que un
  bare clone fresco (sin working tree) también los trae listos.
- **Preocupación real, descartada:** `nix flake` filtra por archivos
  *trackeados por git* cuando el flake vive dentro de un repo git -- sin
  `.git`, cae al fetcher `path:` (copia el directorio tal cual). Probado
  `nix flake metadata`/`nix eval` sobre el work tree de prueba (sin `.git`,
  solo `.got`) y salió limpio, exit 0, sin warnings. Incluso con un symlink
  `result` de prueba presente (como el que deja `nixos-rebuild build` en
  `/nixdots` real) -- Nix lo copia sin quejarse, y de paso `got status` ya
  lo ignora solo (respeta `.gitignore`, que sigue en el repo con
  `result`/`result-*`/`.direnv/`/`*.swp`).

### Pasos reales sobre `/nixdots`

1. `git clone --bare` del remoto real a `~/nixdots.git` -- repo bare
   canónico, independiente del checkout viejo (paso aditivo, no tocó
   `/nixdots` todavía).
2. `mv /nixdots ~/nixdots-git-backup` -- el `mv` no pudo borrar el propio
   directorio `/nixdots` de `/` (permiso denegado, `/` no es escribible por
   `ale`), pero sí alcanzó a copiar y vaciar todo el contenido hacia el
   backup antes de fallar en ese último paso. Resultado neto: `/nixdots`
   quedó vacío (backup íntegro en `~/nixdots-git-backup`, confirmado con
   `diff -rq` sin diferencias) -- justo lo que `got checkout` necesita.
3. `got checkout ~/nixdots.git /nixdots` -- work tree nuevo, directo en el
   path real. `diff -rq` contra el backup (excluyendo `.git`/`.got`/
   `result`) salió vacío.
4. Confirmado sin residuos: `/nixdots/.git` ya no existe.

### Ajustes de código que dependían de `git`

- **`home/ale/home.nix`, función `nixos-update`:** usaba
  `git diff --quiet`/`git add`/`git commit` para el commit automático de
  `flake.lock` tras cada actualización. Cambiado a
  `got status flake.lock` (vacío si no hay cambios) +
  `got commit -m "..." flake.lock` -- sin firma, a diferencia de antes.
- **`modules/desktop.nix`, comentario de `got`:** ya no describe un
  escenario de coexistencia con `git` en el mismo repo (ronda 2026-07-16,
  ya obsoleta) -- ahora documenta que `/nixdots` es un work tree de `got`
  sin `.git`, y que `programs.git` se mantiene a nivel de sistema solo por
  otros repos ajenos a `/nixdots`.

### BUG real (de esta misma migración), corregido: `got commit` no encontraba autor

El primer `got commit` real sobre `/nixdots` falló con `GOT_AUTHOR
environment variable is not set`. Según `got.1`/`got.conf.5`, el orden de
resolución del autor es: variable de entorno `GOT_AUTHOR` → `got.conf` del
repo → `user.name`/`user.email` en el `.git/config` del propio repo → **solo
como último recurso**, `~/.gitconfig` global de Git. Este sistema gestiona
la identidad de git vía home-manager en formato **XDG**
(`~/.config/git/config`, confirmado con `cat`) -- **no** existe
`~/.gitconfig` en `$HOME`, así que `got` no tenía de dónde sacar el autor
por ningún lado. (La suposición inicial de esta misma sección, de que `got`
sí leía la identidad desde `~/.gitconfig`/`programs.git`, era incorrecta --
corregida acá tras reproducir el fallo en vivo.)

**Fix:** declarado el autor directo en `got.conf` del repo bare
(`~/nixdots.git/got.conf`):

```
author "ale <ale_bnes@tuta.com>"
```

Es la vía nativa de `got` (tiene prioridad sobre cualquier config de git) y
no depende de dónde ni cómo esté declarada la identidad de git en el
sistema. Confirmado con un commit real: `got log` mostró
`ale <ale_bnes@tuta.com>` como autor sin volver a pedir `GOT_AUTHOR`.

### Qué NO se tocó

- El paquete `git` sigue en `environment.systemPackages`
  (`hosts/ale/configuration.nix`) y `programs.git` en `home.nix` -- útiles
  para otros repos ajenos a `/nixdots` y necesarios para que `got` resuelva
  el autor de los commits (ver arriba). No se pidió sacar `git` del sistema,
  solo del flujo de este repo.
- `~/nixdots-git-backup` se dejó como red de seguridad (historia completa
  de `git`, por si hace falta consultar algo que `got log` no muestre
  igual) -- no se borró.

## zola sacado del sistema global, espacio de trabajo dedicado en `~/website` (2026-07-22)

A pedido del usuario: `zola` (agregado a `home.packages` el 2026-07-17,
ver sección "zola" arriba) sale de `home/ale/home.nix` -- ya no se instala
a nivel de sistema. En su lugar, `~/website` es un devShell de Nix propio
para el repo real del sitio (`Ale/wesite.git` en el Forgejo de `pcale`,
tema Duckquill sobre Zola, dominio `nezzontli.xyz`), con **zola pineado a
0.18.0 exacto** -- la versión real que corre el servidor OpenBSD que
publica el sitio (confirmado contra el propio historial de commits del
repo: *"el fix anterior de highlighting asumía Zola 0.22, el servidor
corre 0.18.0"*, *"agregue configuracion para openBSD ya que usa Zola
0.18.0"*). El `README.md` del propio repo del sitio dice "Zola v0.21.0+"
-- inconsistente con el servidor real; señalado al usuario, no corregido
(no se tocó ningún archivo del sitio salvo agregar el flake).

- **Revisión de nixpkgs con zola == 0.18.0 exacto:**
  `c3392ad349a5227f4a3464dce87bcc5046692fce` -- encontrada vía nixhub.io y
  **verificada de forma independiente** con `nix eval --raw
  "github:NixOS/nixpkgs/c3392ad349a5227f4a3464dce87bcc5046692fce#zola.version"`
  (no se confió en la fuente externa sin comprobar contra Nix real).
- **`~/website/flake.nix`**: un solo `devShells.x86_64-linux.default` con
  `pkgs.zola` de esa revisión pineada -- independiente del `nixpkgs`
  (nixos-unstable, zola 0.22.1) del resto del sistema. Confirmado con `nix
  develop ~/website -c zola --version` → `zola 0.18.0` real.
- **`~/website` es un work tree de `got`, no `git`** -- mismo patrón que la
  migración de `/nixdots` de esta misma sesión: repo bare canónico en
  `~/website.git` (clonado de
  `ssh://git@pcale.tail32b955.ts.net:2222/Ale/wesite.git`, que ya existía
  con historial real), `got.conf` con el autor declarado ahí mismo (mismo
  fix que en `~/nixdots.git/got.conf`, ver sección de arriba -- este
  sistema no tiene `~/.gitconfig` clásico, solo el XDG
  `~/.config/git/config`, que `got` no lee).
- El repo del sitio trae mezclado el historial completo de upstream del
  tema Duckquill (miles de commits ajenos al sitio real, probablemente de
  un `git subtree`/merge en algún punto) -- no se tocó, es preexistente y
  ajeno a este cambio.
- No había instalación imperativa de `zola` en `nix profile list` (la
  duplicación que había quedado pendiente el 2026-07-17 ya no está) -- no
  hizo falta limpiar nada ahí.

## Bootstrap en una PC nueva, con got puro (2026-07-22)

A pedido del usuario: documentado cómo llevar `/nixdots` a una máquina
recién instalada, dado que el repo real vive en un Forgejo solo accesible
por Tailscale (`pcale.tail32b955.ts.net`), y ahora el repo local es un
work tree de `got`, no de `git`. Probadas tres rutas reales, en orden:

### Ruta 1, descartada: `got clone` por SSH al Forgejo real + Tailscale

Funciona (`got clone`/`got checkout` nativos, probado end-to-end en un
directorio descartable), pero exige levantar Tailscale a mano *antes* del
primer switch (huevo y gallina: Tailscale lo configura este mismo repo) --
más pasos de los necesarios si hay una alternativa más simple.

### Ruta 2, descartada: `got clone` por HTTPS o SSH al espejo de GitHub

- **HTTPS falla, bug real de `got` 0.126:** `got clone
  https://github.com/Richard7987/Nix-Dotfiles.git` da
  `got-fetch-http: bufio_starttls` / `unexpected end of file`,
  reproducido dos veces. Descartado que sea de red: `curl`/`openssl
  s_client` contra github.com funcionan perfecto (TLS y HTTP/2 sanos). Es
  el cliente HTTP(S) minimalista propio de `got` (no usa libcurl como
  `git`), que no tolera bien cómo GitHub sirve el protocolo smart HTTP
  (HTTP/2, chunked encoding, etc.) -- no encontrado como bug documentado
  en búsquedas, pero 100% reproducible en esta máquina.
- **SSH sí funciona:** `got clone git@github.com:Richard7987/Nix-Dotfiles.git`
  probado end-to-end con éxito (`got.conf` con el remote armado solo, HEAD
  del checkout `5bb6e64...` idéntico al del Forgejo real -- confirma que
  el espejo está al día). Requiere que la llave SSH de la YubiKey esté
  agregada a la cuenta de GitHub -- confirmado que ya lo está
  (`ssh -T git@github.com` → "Hi Richard7987!"). El host key de GitHub se
  agregó a `known_hosts` tras verificar el fingerprint ED25519
  (`SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU`) contra la
  documentación oficial de GitHub, no a ciegas.
- Descartada de todos modos porque exige el bootstrap manual de
  gpg-agent/YubiKey-SSH *antes* del primer switch (mismo problema de
  huevo y gallina que la ruta 1, aunque sin depender de Tailscale).

### Ruta 3, elegida: `git clone --bare` (una sola vez) + `got` para todo lo demás

El espejo de GitHub (`https://github.com/Richard7987/Nix-Dotfiles.git`)
es **público** -- `git clone --bare` funciona sin ninguna autenticación,
sin YubiKey, sin Tailscale (probado real, HEAD `5bb6e64...` idéntico al
Forgejo). `git` tolera sin problema lo mismo que rompe a `got` por HTTPS,
así que se usa una sola vez, solo para bajar los objetos -- desde el
`got checkout` en adelante todo el flujo es 100% `got`, igual que el
resto de este repo.

**Detalle importante:** el remote que dejó `git clone` en el `config` del
bare repo apunta a `https://github.com/...` -- el mismo protocolo que
falla en `got`. Hay que sobreescribir `got.conf` con el remote real
(`ssh://git@pcale.tail32b955.ts.net:2222/...`) antes de usar `got
fetch`/`got send`, o quedaría sirviendo solo para lectura vía checkout
inicial. Procedimiento completo documentado en el README, sección
"Bootstrap en una PC nueva".
