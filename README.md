# Nix-Dotfiles — configuración NixOS de ale

Flake para migrar esta PC de FreeBSD a NixOS con Hyprland + [Noctalia](https://docs.noctalia.dev/).

## Qué incluye

- **Hyprland** (config en Lua, `home/ale/hyprland.lua`) + **Noctalia shell** y **Noctalia Greeter**
  (`modules/desktop.nix`, `home/ale/home.nix`).
- **Gráficos duales Intel + Nvidia** en modo PRIME *sync*, con Steam/gamemode/CUDA
  (`modules/graphics.nix`).
- **YubiKey** para GPG + SSH vía `pcscd`/`gpg-agent`, con el comando `yubico` de
  recuperación (`modules/yubikey.nix`, `home/ale/home.nix`).
- **Tailscale** con exit node de Mullvad fijado automáticamente al arrancar
  (`modules/tailscale.nix`).
- **sudo** (con reglas `NOPASSWD` puntuales para `tailscale` y el restart de
  `pcscd`, ver `modules/yubikey.nix`), **zen-browser** y **Kleopatra**.
- **Bluetooth** + fix de AVRCP para controles de reproducción, y **LibrePods**
  para controlar AirPods (modos de ruido, batería, etc.) — ver sección
  dedicada más abajo, la instalación del AppImage es manual.

## Antes del primer `nixos-rebuild switch`

**✅ Ya resuelto (máquina instalada y en uso desde 2026-07-12/13, ver
`NOTES.md` ronda #12).** Queda como referencia histórica de lo que había
que ajustar al migrar desde la sesión de FreeBSD:

Ya resueltas desde el armado inicial: terminal (kitty), teclado (`us` +
variante `altgr-intl`, así `AltGr+n` da `ñ`), navegador (`zen-beta`), zona
horaria (`America/Mexico_City`) y audio (pipewire + wireplumber, ya
activado en `modules/desktop.nix`).

Los 4 `AJUSTAR` que dependían de hardware real ya se resolvieron todos
contra la máquina real:

1. **`hosts/ale/hardware-configuration.nix`** — ✅ reemplazado por el real
   generado por `nixos-generate-config`.
2. **`system.stateVersion` / `home.stateVersion`** — ✅ ambos en `"26.05"`
   (valor real del instalador). **Nunca se cambia después.**
3. **`modules/graphics.nix`** — ✅ `intelBusId`/`nvidiaBusId` confirmados
   contra `lspci -D | grep -E "VGA|3D"` real (`0000:00:02.0` Intel,
   `0000:01:00.0` Nvidia).
4. **`home/ale/hyprland.lua`** — ✅ nombre de monitor confirmado con
   `hyprctl monitors` real: sí es `"eDP-1"`.

## Validado con `nix eval` real

Esta config fue evaluada de punta a punta con Nix real (instalado vía `pkg
install nix` en la sesión de FreeBSD donde se armó, usando un store local
sin privilegios: `NIX_REMOTE="local?root=$HOME/.nix-testroot"`). Con un
`fileSystems."/"` temporal de prueba (revertido después),
`config.system.build.toplevel.drvPath` se construyó sin errores, todas las
`assertions` del sistema evaluaron `true`, y cada paquete referenciado en
`environment.systemPackages`/`home.packages` resolvió contra el nixpkgs
real. `flake.lock` en este repo viene de esa corrida. Sigue habiendo cosas
que solo se pueden probar en la máquina real (arranque, hardware, sesión
gráfica) — ver "Antes del primer switch" arriba.

## Primer despliegue

```sh
# clona esto en la máquina NixOS (o usa este mismo checkout si ya migraste)
sudo nixos-rebuild build --flake .#ale   # primero build, para detectar errores sin aplicar
sudo nixos-rebuild switch --flake .#ale
```

## Después del primer switch

- **✅ YubiKey/GPG** — hecho y verificado de punta a punta (llave importada,
  confianza ultimate, commit de prueba firmado y verificado con
  `git log --show-signature`). Comandos para referencia (ej. si reinstalas):

  ```sh
  gpg --keyserver-options no-self-sigs-only \
    --fetch-key https://codeberg.org/Richard7987/gpg-keys/raw/branch/main/ale_bnes.pub.asc
  # marca ultimate (no interactivo -- "trust" pide nivel 1-5 + confirmación):
  echo -e "5\ny\n" | gpg --no-tty --command-fd 0 --edit-key DBD5F61D8A0A14D7 trust quit
  ```

  (Antes tenía `--recv-keys --fetch-key <url>` en un mismo comando -- gpg los
  trata como dos "comandos" distintos e incompatibles entre sí, tira
  "órdenes incompatibles". Ya corregido.)

  Con la YubiKey insertada, prueba `gpg --card-status` y `ssh-add -L`. Si algo
  se traba, usa el comando `yubico` (definido en tu zsh). **SSH ya funcionaba
  solo** desde el primer switch (`services.gpg-agent.enableSshSupport`), sin
  necesitar ningún paso extra.
- **✅ Tailscale** — autenticado, exit node `mullvad-exit` activo y
  persistido. Para referencia (primera vez / si reinstalas):

  ```sh
  sudo tailscale up
  ```

  El exit node se fija solo después de esto vía el servicio
  `tailscale-exit-node` — a diferencia de FreeBSD, aquí no depende de ningún
  driver wifi con fallos intermitentes.
- **✅ Noctalia** — los atajos `mainMod+Space` / `+S` / `+comma` ya están
  declarados en `hyprland.lua` con el comando IPC real (`noctalia msg
  panel-toggle ...` / `settings-toggle`), confirmado contra la doc oficial.
  Ya no es "revisa si funciona por su cuenta" — está resuelto explícito.
- **❌ LibrePods (AirPods) — sigue pendiente, es manual a propósito.** No hay
  paquete Nix oficial (el proyecto está reescribiéndose de Qt6/C++ a Rust, y
  en Linux solo publica AppImages nightly como artifacts de GitHub Actions,
  sin URL estable para fijar por hash). Descarga manual, una vez y cada vez
  que quieras actualizar:
  1. https://github.com/kavishdevar/librepods/actions/workflows/ci-linux-rust.yml
  2. Entra al run exitoso más reciente → Artifacts → descarga el AppImage
     (necesitas sesión de GitHub, los artifacts están detrás de login)
  3. `mkdir -p ~/Applications && mv LibrePods*.AppImage ~/Applications/LibrePods.AppImage && chmod +x ~/Applications/LibrePods.AppImage`
  4. Corre `librepods` (alias ya configurado, usa `appimage-run` por debajo)

  El fix de AVRCP para que play/pause/skip funcionen desde los AirPods ya
  está aplicado a nivel de sistema
  (`services.pipewire.wireplumber.extraConfig` en `modules/desktop.nix`), se
  aplica solo en cada `nixos-rebuild switch` — esta parte **no** requiere
  nada manual, solo la descarga del AppImage en sí.
