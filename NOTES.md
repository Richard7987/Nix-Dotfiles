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
