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
- **doas** en vez de sudo, **zen-browser** y **Kleopatra**.

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
  doas tailscale up
  ```
  El exit node de Mullvad (`mullvad-exit`) se fija solo después de esto vía
  el servicio `tailscale-exit-node`, y queda persistido para los siguientes
  arranques — a diferencia de FreeBSD, aquí no depende de ningún driver wifi
  con fallos intermitentes.
- **Noctalia**: si `mainMod+Space` / `+S` / `+,` no abren el launcher/control
  center/settings, revisa si Noctalia ya trae esos keybinds por su cuenta
  antes de activar el bloque comentado al final de `hyprland.lua`.

## Subir a GitHub

```sh
git add -A
git commit -m "Config inicial NixOS: Hyprland + Noctalia, YubiKey, Tailscale, gráficos duales"
git push -u origin main
```
