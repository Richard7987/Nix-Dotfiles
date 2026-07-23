# nixdots

Configuración NixOS de `ale` — laptop Intel+Nvidia con Hyprland +
[Noctalia](https://docs.noctalia.dev/). Desplegada vía flake, sin
gestión de secretos (la clave GPG vive en una YubiKey).

## Estructura

```
flake.nix                        # inputs y nixosConfigurations.ale
hosts/ale/
  configuration.nix              # boot, red, locale, usuario, nix.settings
  hardware-configuration.nix     # generado por nixos-generate-config
modules/
  desktop.nix                    # Hyprland, Noctalia (+greeter), audio, fuentes, paquetes de sistema
  graphics.nix                   # PRIME sync Intel/Nvidia, Steam, gamemode, CUDA
  yubikey.nix                    # pcscd, sudo (reglas NOPASSWD puntuales)
  tailscale.nix                  # exit node de Mullvad fijado al arrancar
home/ale/
  home.nix                       # home-manager: zsh/p10k, git, gpg-agent, LibrePods, paquetes de usuario
  hyprland.lua                   # config de Hyprland (Lua, no hyprland.conf)
  p10k.zsh                       # prompt Powerlevel10k
pkgs/
  librepods.nix                  # LibrePods (control AirPods) compilado de fuente
```

## Stack

- **Hyprland** + **Noctalia** (shell y greeter), tema Gruvbox, wallpapers vía
  `github:AngelJumbo/gruvbox-wallpapers`.
- **Gráficos duales** Intel/Nvidia en modo PRIME *sync* (driver propietario,
  `legacy_580` — esta GPU es Pascal). Steam + gamemode + CUDA.
- **YubiKey** para GPG/SSH (`pcscd` + `gpg-agent`, comando `yubico` para
  reiniciarla si deja de responder).
- **Tailscale** con exit node de Mullvad.
- **sudo**, con `wheel` normal + NOPASSWD puntual para `pcscd`/`tailscale`.
- **Bluetooth/AirPods**: LibrePods compilado de fuente (`pkgs/librepods.nix`),
  fix de AVRCP para play/pause/skip, códec A2DP restringido a SBC/AAC.
- **zsh**: Oh My Zsh + Powerlevel10k + fzf-tab + autosuggestions + syntax
  highlighting.
- Theming Qt coherente (Kleopatra, pinentry-qt) vía `plasma-integration`.

## Uso

Primer despliegue:

```sh
sudo nixos-rebuild build --flake .#ale   # detecta errores sin aplicar
sudo nixos-rebuild switch --flake .#ale
```

Actualizar el sistema (flake update + build + switch + commit de
`flake.lock` si cambió):

```sh
nixos-update   # función de zsh, definida en home/ale/home.nix
```

Si la YubiKey deja de responder:

```sh
yubico   # función de zsh: reinicia pcscd + gpg-agent
```

## Notas

El *por qué* de cada decisión (y el historial de auditorías/bugs
encontrados durante la migración desde FreeBSD) está en [`NOTES.md`](NOTES.md).
