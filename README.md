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

Ya resueltas: terminal (kitty), teclado (`us` + variante `altgr-intl`, así
`AltGr+n` da `ñ`), navegador (`zen-beta`), zona horaria (`America/Mexico_City`)
y audio (pipewire + wireplumber, ya activado en `modules/desktop.nix`).

Quedan pendientes, porque dependen de hardware que no puedo ver desde esta
sesión (sigo en la FreeBSD actual, no en la NixOS futura). Busca `AJUSTAR` en
los archivos:

1. **`hosts/ale/hardware-configuration.nix`** — es un placeholder. Reemplázalo
   por el que genera `nixos-generate-config` (o el que ya tengas en
   `/etc/nixos/hardware-configuration.nix` si ya instalaste NixOS).
2. **`hosts/ale/configuration.nix`** y **`home/ale/home.nix`** —
   `system.stateVersion` / `home.stateVersion`: pon el valor real que te dé el
   instalador. **Nunca lo cambies después.**
3. **`modules/graphics.nix`** — bus IDs de Intel/Nvidia. Corre
   `lspci -D | grep -E "VGA|3D"` en la máquina real y ajusta `intelBusId` /
   `nvidiaBusId` (la fórmula está explicada en el comentario del archivo).
4. **`home/ale/hyprland.lua`** — nombre de monitor (`hyprctl monitors`, línea
   `hl.workspace_rule` con `"eDP-1"` como placeholder).

## Primer despliegue

```sh
# clona esto en la máquina NixOS (o usa este mismo checkout si ya migraste)
sudo nixos-rebuild build --flake .#ale   # primero build, para detectar errores sin aplicar
sudo nixos-rebuild switch --flake .#ale
```

## Después del primer switch

- **YubiKey/GPG**: importa tu clave pública y confía en ella:

  ```sh
  gpg --keyserver-options no-self-sigs-only \
    --recv-keys --fetch-key https://codeberg.org/Richard7987/gpg-keys/raw/branch/main/ale_bnes.pub.asc
  gpg --edit-key DBD5F61D8A0A14D7 trust   # marca ultimate
  ```

  Con la YubiKey insertada, prueba `gpg --card-status` y `ssh-add -L`. Si algo
  se traba, usa el comando `yubico` (definido en tu zsh).
- **Tailscale**: primera autenticación manual (una sola vez):

  ```sh
  sudo tailscale up
  ```

  El exit node de Mullvad (`mullvad-exit`) se fija solo después de esto vía
  el servicio `tailscale-exit-node`, y queda persistido para los siguientes
  arranques — a diferencia de FreeBSD, aquí no depende de ningún driver wifi
  con fallos intermitentes.
- **Noctalia**: si `mainMod+Space` / `+S` / `+,` no abren el launcher/control
  center/settings, revisa si Noctalia ya trae esos keybinds por su cuenta
  antes de activar el bloque comentado al final de `hyprland.lua`.
- **LibrePods (AirPods)**: no hay paquete Nix oficial (el proyecto está
  reescribiéndose de Qt6/C++ a Rust, y en Linux solo publica AppImages
  nightly como artifacts de GitHub Actions, sin URL estable para fijar por
  hash). Descarga manual, una vez y cada vez que quieras actualizar:
  1. https://github.com/kavishdevar/librepods/actions/workflows/ci-linux-rust.yml
  2. Entra al run exitoso más reciente → Artifacts → descarga el AppImage
     (necesitas sesión de GitHub, los artifacts están detrás de login)
  3. `mkdir -p ~/Applications && mv LibrePods*.AppImage ~/Applications/LibrePods.AppImage && chmod +x ~/Applications/LibrePods.AppImage`
  4. Corre `librepods` (alias ya configurado, usa `appimage-run` por debajo)

  El fix de AVRCP para que play/pause/skip funcionen desde los AirPods ya
  está aplicado a nivel de sistema
  (`services.pipewire.wireplumber.extraConfig` en `modules/desktop.nix`), se
  aplica solo en cada `nixos-rebuild switch`.
