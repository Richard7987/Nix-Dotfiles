# nixdots

Configuración NixOS de `ale` — laptop Intel+Nvidia con Hyprland +
[Noctalia](https://docs.noctalia.dev/). Desplegada vía flake, sin
gestión de secretos (la clave GPG vive en una YubiKey).

Versionado con **git** (2026-07-28: vuelto de `got` a `git` -- ver
"Migración de vuelta a git" en [`NOTES.md`](NOTES.md); antes, entre
2026-07-22 y esa fecha, usó [got](https://gameoftrees.org/)). `/nixdots`
es un repo git normal, con `origin` apuntando al Forgejo propio vía
Tailscale (`ssh://git@pcale.tail32b955.ts.net:2222/Ale/Nix-Dotfiles.git`).

Importa que sea un repo git de verdad (no solo un directorio suelto) para
que `nix flake` filtre correctamente qué archivos entran al flake -- Nix
usa el índice de git (`git ls-files`, respetando `.gitignore`) para
decidir qué es parte del source del flake, y avisa con
`warning: Git tree '/nixdots' is dirty` si hay cambios sin commitear
(confirmado corriendo `nix flake check`/`nix build` en vivo). Con `got`
como VCS, Nix no tenía ninguna de esas dos señales.

`programs.git.signing.signByDefault = true` (`home/ale/home.nix`) firma
todo commit con la YubiKey (GPG) automáticamente -- a diferencia de
`got commit`, que no soporta firma en absoluto.

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

## Bootstrap en una PC nueva

El repo real vive en un Forgejo solo accesible por Tailscale
(`pcale.tail32b955.ts.net`) -- pero en una PC recién instalada no hay
Tailscale ni YubiKey configurados todavía (huevo y gallina: Tailscale lo
levanta este mismo repo). Por eso el clone inicial se hace contra el
espejo **público** en GitHub (sin autenticación), y recién después se
repunta `origin` al Forgejo real:

```sh
# 1. clone inicial desde el espejo público (sin YubiKey ni Tailscale)
nix-shell -p git
git clone https://github.com/Richard7987/Nix-Dotfiles.git /nixdots

# 2. una vez que Tailscale + la YubiKey (GPG/SSH) ya estén andando,
#    repuntar origin al Forgejo real
cd /nixdots
git remote set-url origin ssh://git@pcale.tail32b955.ts.net:2222/Ale/Nix-Dotfiles.git
git fetch origin
```

Con `got` este bootstrap necesitaba un `git clone --bare` + `got.conf`
armado a mano + `got checkout` en tres pasos (el cliente HTTP propio de
`got` no tolera cómo GitHub sirve HTTPS -- ver "Migración de vuelta a
git" en `NOTES.md`); con `git` de punta a punta es solo esto.

Después: ajustar los placeholders de hardware (`hosts/ale/hardware-configuration.nix`,
bus IDs en `modules/graphics.nix`, nombre de monitor en `home/ale/hyprland.lua`)
y recién ahí el primer despliegue.

## Firmar un release (tag)

Los commits de este repo ya salen firmados solos (GPG vía YubiKey,
`programs.git.signing.signByDefault = true`). Para marcar una versión,
un tag firmado con la misma llave:

```sh
cd /nixdots
git tag -s -m "mensaje describiendo esta versión" v2026.07.28
git push origin v2026.07.28
git tag -v v2026.07.28   # verifica la firma
```

Esquema de versión: **CalVer** (`vAAAA.MM.DD`) -- cada tag es una foto
fechada del sistema, sin tener que decidir qué cuenta como cambio
"mayor" o "menor" (no hay una API que romper en un repo de dotfiles).

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
