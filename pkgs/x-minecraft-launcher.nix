# X Minecraft Launcher (XMCL, voxelum/x-minecraft-launcher) empaquetado desde
# el AppImage oficial de GitHub Releases.
#
# NO se compila de fuente (a diferencia de librepods.nix): es un monorepo
# Electron + Vue + pnpm workspaces con módulos nativos -- una build Nix desde
# cero sería un esfuerzo comparable a empaquetarlo para nixpkgs mismo, y no
# hay flake/derivación comunitaria existente (confirmado buscando). El
# AppImage x64 sí es 100% reproducible acá: fetchurl fija versión + hash, no
# es un "bajar a mano" fuera de Nix.
#
# appimageTools.wrapType2 arma el FHS env (libs de Electron/Chromium) y
# extrae el binario real -- confirmado en vivo contra el contenido
# desempaquetado del AppImage (appimageTools.extractType2):
#   - Exec real del .desktop upstream: "AppRun --no-sandbox %U" (AppRun solo
#     exportaba LD_LIBRARY_PATH/XDG_DATA_DIRS y ejecutaba el binario `xmcl`)
#   - Icono: xmcl.png en usr/share/icons/hicolor/512x512/apps/
#   - `--no-sandbox` es necesario porque el `chrome-sandbox` setuid que trae
#     el AppImage no tiene los permisos correctos fuera de su entorno
#     original -- mismo motivo por el que el .desktop upstream ya lo pasaba.
#
# Build + smoke test verificados en vivo en esta máquina: `nix build` con
# esta derivación compila, y `x-minecraft-launcher --version` corre y
# devuelve "0.65.1" sin abrir ventana.
#
# Actualizar versión: bajar el nuevo tag de
# https://github.com/voxelum/x-minecraft-launcher/releases, actualizar
# `version` y recalcular `hash` con
# `nix-prefetch-url --type sha256 <url-del-.AppImage>` + `nix hash convert
# --hash-algo sha256 --to sri <hash>`.
{ lib, appimageTools, fetchurl }:

let
  pname = "x-minecraft-launcher";
  version = "0.65.1";

  src = fetchurl {
    url = "https://github.com/voxelum/x-minecraft-launcher/releases/download/v${version}/xmcl-${version}-x86_64.AppImage";
    hash = "sha256-t1+JT9OEJSLPnoEfCLo7b7ai9aLYdAaz8gxdqLfTIUw=";
  };

  appimageContents = appimageTools.extractType2 { inherit pname version src; };
in
appimageTools.wrapType2 {
  inherit pname version src;

  extraInstallCommands = ''
    install -Dm444 ${appimageContents}/xmcl.desktop -t $out/share/applications
    install -Dm444 ${appimageContents}/usr/share/icons/hicolor/512x512/apps/xmcl.png -t $out/share/icons/hicolor/512x512/apps
    substituteInPlace $out/share/applications/xmcl.desktop \
      --replace-fail 'Exec=AppRun --no-sandbox %U' 'Exec=${pname} --no-sandbox %U'
  '';

  meta = with lib; {
    description = "Fully featured Minecraft launcher (mods, modpacks, CurseForge/Modrinth integration)";
    homepage = "https://github.com/voxelum/x-minecraft-launcher";
    license = licenses.mit; # confirmado en el LICENSE real del repo
    platforms = [ "x86_64-linux" ];
    mainProgram = "x-minecraft-launcher";
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
  };
}
