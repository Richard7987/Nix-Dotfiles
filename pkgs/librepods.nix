# LibrePods (control de AirPods -- ruido, batería, etc.) compilado de fuente.
# No hay paquete Nix oficial ni release de Linux en GitHub (solo APKs de
# Android en Releases) -- el binario Linux real vive en la rama `linux/rust`
# de una PR sin mergear (kavishdevar/librepods#241). Es un proyecto Cargo
# normal (no depende de nada específico de AppImage en runtime, el AppImage
# solo empaqueta el binario + ícono + .desktop), así que se compila directo
# acá en vez de depender del AppImage nightly de GitHub Actions (que requiere
# login y no tiene URL fija/hasheable).
#
# Pineado a un commit específico (no a la rama) para que el hash de fetchFromGitHub
# sea estable -- actualizar `rev`/`hash` a mano cuando quieras una versión más
# nueva (`nix flake prefetch "github:kavishdevar/librepods/<rev>"` da el hash).
# Build verificado en vivo en esta máquina: compila, autoPatchelfHook resuelve
# las libs de runtime (vulkan-loader/wayland/libpulseaudio/dbus) sin faltantes,
# y `librepods --help` corre bien.
{ lib
, rustPlatform
, fetchFromGitHub
, pkg-config
, dbus
, libpulseaudio
, vulkan-loader
, libxkbcommon
, wayland
, fontconfig
, freetype
, makeWrapper
, autoPatchelfHook
}:

rustPlatform.buildRustPackage rec {
  pname = "librepods";
  version = "unstable-2026-07-13";

  src = fetchFromGitHub {
    owner = "kavishdevar";
    repo = "librepods";
    rev = "672e65ad36eebf21ff1c1a508066f9197ee56d17"; # rama linux/rust, sin mergear (PR #241)
    hash = "sha256-EuIYvBqBtpgutVqPOLIO3E9OhVzQ5q5TDoz/F+9MHEE=";
  };

  sourceRoot = "${src.name}/linux-rust";

  cargoLock.lockFile = "${src}/linux-rust/Cargo.lock";

  # "Unknown Control Command identifier: 0x3e" -- 0x3e es un byte del protocolo
  # propietario AACP de Apple que esta versión de librepods todavía no mapea
  # (reversing incompleto upstream, no algo que podamos "arreglar" adivinando
  # qué significa). Es inofensivo -- solo baja el nivel de log de error! a
  # debug! para que no se vea como un error real cuando no rompe nada.
  # sed en vez de substituteInPlace multilínea: los strings ''...'' de Nix
  # re-indentan el contenido automáticamente, lo que rompe el matching por
  # espacios exactos (ya me pasó -- "pattern doesn't match anything"). -z
  # trata el archivo completo como una sola cadena para poder matchear a
  # través del salto de línea sin depender de la indentación real del archivo.
  postPatch = ''
    sed -i -z -E 's/error!\(\s*\n\s*"Unknown Control Command identifier/debug!(\n                        "Unknown Control Command identifier/' src/bluetooth/aacp.rs
  '';

  nativeBuildInputs = [ pkg-config makeWrapper autoPatchelfHook ];
  buildInputs = [ dbus libpulseaudio fontconfig freetype ];

  # iced/wgpu necesitan encontrar Vulkan/Wayland en runtime -- autoPatchelfHook
  # arregla el rpath del binario, pero estas libs deben estar disponibles.
  runtimeDependencies = [ vulkan-loader libxkbcommon wayland ];

  postInstall = ''
    install -Dm644 assets/icon.png $out/share/icons/hicolor/256x256/apps/me.kavishdevar.librepods.png
    install -Dm644 assets/me.kavishdevar.librepods.desktop $out/share/applications/me.kavishdevar.librepods.desktop
  '';

  meta = with lib; {
    description = "Control AirPods (noise control, battery, etc.) on Linux";
    homepage = "https://github.com/kavishdevar/librepods";
    license = licenses.agpl3Only; # confirmado en el LICENSE real del repo
    platforms = platforms.linux;
    mainProgram = "librepods";
  };
}
