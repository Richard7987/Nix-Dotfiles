# Nokkvi (cliente de música nativo para Navidrome, github.com/f-o-o-g-s/nokkvi).
# A diferencia de LibrePods, acá SÍ hay releases oficiales de Linux con
# binario prebuilt -- pero el Cargo.toml del proyecto pinea `iced` a un
# commit de la rama `master` upstream (no crates.io), lo que haría que
# compilarlo de fuente con buildRustPackage dependa de un outputHashes
# frágil que se puede romper con cada bump de esa fork. Por eso acá se usa
# el binario oficial del release + autoPatchelfHook, en vez de compilar
# (decisión tomada con el usuario, ver conversación -- prefirió esto a
# nix-ld genérico + descarga manual sin declarar).
#
# El hash del tarball es el mismo `sha256` que publica el proyecto junto al
# release (ver <url>.sha256 en la misma release de GitHub), así que además
# de fijar la build es una verificación de integridad contra lo que firma
# el autor. Para actualizar: cambiar `version` y `hash` (bajar el .sha256
# del nuevo release y convertirlo con
# `nix hash convert --hash-algo sha256 --to sri <hex>`).
{ lib
, stdenv
, fetchurl
, autoPatchelfHook
, fontconfig
, freetype
, alsa-lib
, pipewire
, vulkan-loader
, libxkbcommon
, wayland
}:

stdenv.mkDerivation rec {
  pname = "nokkvi";
  version = "0.16.0";

  src = fetchurl {
    url = "https://github.com/f-o-o-g-s/nokkvi/releases/download/v${version}/nokkvi-v${version}-x86_64-unknown-linux-gnu.tar.gz";
    hash = "sha256-SmBVYD2T6beJLGPoBeTktborhXP4jBaZSIdTQfo9Szs=";
  };

  nativeBuildInputs = [ autoPatchelfHook ];

  # Dependencias directas del binario (confirmado con `readelf -d`):
  # libfontconfig, libfreetype, libasound (ALSA), libpipewire-0.3, libgcc_s
  # (stdenv.cc.cc.lib -- el runtime de gcc, no viene con ningún paquete de
  # arriba, autoPatchelfHook no la encuentra si no se agrega a mano).
  buildInputs = [ fontconfig freetype alsa-lib pipewire stdenv.cc.cc.lib ];

  # iced/wgpu (mismo stack que LibrePods) resuelven Vulkan/Wayland en
  # runtime vía dlopen, no aparecen en `readelf -d` -- autoPatchelfHook
  # necesita que estén disponibles igual para que el dlopen no falle.
  runtimeDependencies = [ vulkan-loader libxkbcommon wayland ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 nokkvi $out/bin/nokkvi
    install -Dm644 assets/org.nokkvi.nokkvi.desktop $out/share/applications/org.nokkvi.nokkvi.desktop
    install -Dm644 assets/org.nokkvi.nokkvi.svg $out/share/icons/hicolor/scalable/apps/org.nokkvi.nokkvi.svg
    install -Dm644 assets/org.nokkvi.nokkvi.png $out/share/icons/hicolor/512x512/apps/org.nokkvi.nokkvi.png

    runHook postInstall
  '';

  meta = with lib; {
    description = "Native Navidrome music client (Rust/Iced) with PipeWire audio, gapless playback and GPU visualizers";
    homepage = "https://github.com/f-o-o-g-s/nokkvi";
    license = licenses.gpl3Only; # confirmado en Cargo.toml: "GPL-3.0-only"
    platforms = platforms.linux;
    mainProgram = "nokkvi";
  };
}
