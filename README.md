# nixdots

Configuración NixOS de `ale` — laptop Intel+Nvidia con **niri** +
[DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell).
Desplegada vía flake, sin gestión de secretos (la clave GPG vive en una
YubiKey).

Versionado con git; commits firmados con GPG (YubiKey) vía
`programs.git.signing.signByDefault = true`.

## Estructura

```
flake.nix                        # inputs y nixosConfigurations.ale
hosts/ale/
  configuration.nix              # boot, red, locale, usuario, nix.settings
  hardware-configuration.nix     # generado por nixos-generate-config
modules/
  desktop.nix                    # bluetooth, audio (pipewire), greeter DMS, gvfs
  graphics.nix                   # PRIME sync Intel/Nvidia, Steam, gamemode, CUDA
  niri.nix                       # niri + DankMaterialShell (shell, lockscreen)
  yubikey.nix                    # pcscd, sudo (reglas NOPASSWD puntuales)
  tailscale.nix                  # exit node de Mullvad fijado al arrancar
home/ale/
  home.nix                       # home-manager: zsh/p10k, git, gpg-agent, gtk, paquetes de usuario
  niri.kdl                       # config de niri (binds, layout, spawns)
  p10k.zsh                       # prompt Powerlevel10k
pkgs/
  librepods.nix                  # LibrePods (control AirPods) compilado de fuente
  clamui.nix                     # GUI de ClamAV
  x-minecraft-launcher.nix
```

## Stack

- **niri** (compositor scrollable) + **DankMaterialShell** (shell y
  greeter), tema dinámico vía matugen desde el wallpaper.
- **Gráficos duales** Intel/Nvidia en modo PRIME *sync* (driver propietario,
  `legacy_580` — GPU Pascal). Steam + gamemode + CUDA.
- **YubiKey** para GPG/SSH (`pcscd` + `gpg-agent`, comando `yubico` para
  reiniciarla si deja de responder).
- **Tailscale** con exit node de Mullvad.
- **sudo**, con `wheel` normal + NOPASSWD puntual para `pcscd`/`tailscale`.
- **Bluetooth/AirPods**: LibrePods compilado de fuente, fix de AVRCP para
  play/pause/skip, códec A2DP restringido a SBC/AAC.
- **zsh**: Oh My Zsh + Powerlevel10k + fzf-tab + autosuggestions + syntax
  highlighting.
- adw-gtk3 para que apps GTK3 legacy (LibreOffice) hereden el tema dinámico.
- voxtype (dictado), DankCalendar (sync CalDAV/Nextcloud), zen-browser,
  clamui (GUI de ClamAV).

## Bootstrap en una PC nueva

El repo real vive en un Forgejo solo accesible por Tailscale
(`pcale.tail32b955.ts.net`) -- pero en una PC recién instalada no hay
Tailscale ni YubiKey configurados todavía. Por eso el clone inicial se
hace contra el espejo **público** en GitHub (sin autenticación), y recién
después se repunta `origin` al Forgejo real:

```sh
nix-shell -p git
git clone https://github.com/Richard7987/Nix-Dotfiles.git /nixdots

# una vez que Tailscale + la YubiKey (GPG/SSH) ya estén andando:
cd /nixdots
git remote set-url origin ssh://git@pcale.tail32b955.ts.net:2222/Ale/Nix-Dotfiles.git
git fetch origin
```

Después: ajustar los placeholders de hardware
(`hosts/ale/hardware-configuration.nix`, bus IDs en `modules/graphics.nix`,
nombre de monitor en `home/ale/niri.kdl`) y recién ahí el primer despliegue.

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

Firmar un tag de versión (CalVer, `vAAAA.MM.DD`):

```sh
git tag -s -m "mensaje describiendo esta versión" v2026.08.15
git push origin v2026.08.15
git tag -v v2026.08.15   # verifica la firma
```

## Notas

El *por qué* de cada decisión (historial completo de migraciones,
auditorías y bugs encontrados) está en [`NOTES.md`](NOTES.md).
