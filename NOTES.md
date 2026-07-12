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

## Referencias usadas

- https://docs.noctalia.dev/v5/getting-started/nixos/
- https://docs.noctalia.dev/v5/compositor-settings/hyprland/
- https://github.com/noctalia-dev/noctalia
- https://github.com/noctalia-dev/noctalia-greeter
- https://github.com/0xc000022070/zen-browser-flake
- https://wiki.hypr.land/Nix/Hyprland-on-NixOS/
- https://hypr.land/news/26_lua/ (Lua-ificación de la config de Hyprland)
- Código fuente real de los módulos de home-manager (`programs/gpg.nix`,
  `services/gpg-agent.nix`, `programs/git.nix`) y de NixOS
  (`security/doas.nix`, `hardware/video/nvidia.nix`) — opciones verificadas
  ahí, no de memoria.
