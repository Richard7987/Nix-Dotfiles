# ClamUI (interfaz gráfica GTK4/libadwaita para ClamAV) -- no hay paquete
# en nixpkgs ni flake propio (confirmado en el repo), así que se empaqueta
# acá con buildPythonApplication (usa hatchling como build-backend, ver
# pyproject.toml del proyecto). Pineado al tag v0.3.0 (== version del
# pyproject) en vez de master para que el hash sea estable.
#
# clamscan (el binario real de escaneo) NO se agrega como runtime dep acá:
# clamui lo invoca como subproceso vía $PATH, así que clamav se instala a
# nivel de sistema (services.clamav / environment.systemPackages en
# configuration.nix) en vez de quedar atado a este paquete -- igual que
# hace la versión Flatpak oficial, que también requiere clamav en el host.
{ lib
, buildPythonApplication
, fetchFromGitHub
, hatchling
, pygobject3
, pycairo
, psutil
, matplotlib
, requests
, urllib3
, certifi
, keyring
, pillow
, cairosvg
, wrapGAppsHook4
, gobject-introspection
, gtk4
, libadwaita
}:

buildPythonApplication rec {
  pname = "clamui";
  version = "0.3.0";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "linx-systems";
    repo = "clamui";
    tag = "v${version}";
    hash = "sha256-jTtuGpSa1wVrxPYN77sywj6+f/CB3CcL+vnFgLw+UNk=";
  };

  build-system = [ hatchling ];

  dependencies = [
    pygobject3
    pycairo
    psutil
    matplotlib
    requests
    urllib3
    certifi
    keyring
    pillow
    cairosvg
  ];

  nativeBuildInputs = [
    wrapGAppsHook4
    gobject-introspection
  ];

  buildInputs = [
    gtk4
    libadwaita
  ];

  # El proyecto no trae tests empaquetados para pip/hatchling (viven en
  # tests/ pero requieren un entorno GTK con display); se corren upstream
  # vía pytest, no acá.
  doCheck = false;

  # Iconos + .desktop + metainfo no forman parte del paquete Python (viven
  # en data/ e icons/ en la raíz del repo, fuera del paquete `src`), así
  # que se instalan a mano.
  postInstall = ''
    install -Dm644 icons/io.github.linx_systems.ClamUI.svg \
      $out/share/icons/hicolor/scalable/apps/io.github.linx_systems.ClamUI.svg
    install -Dm644 data/io.github.linx_systems.ClamUI.desktop \
      $out/share/applications/io.github.linx_systems.ClamUI.desktop
    install -Dm644 data/io.github.linx_systems.ClamUI.metainfo.xml \
      $out/share/metainfo/io.github.linx_systems.ClamUI.metainfo.xml
  '';

  meta = with lib; {
    description = "GTK4/libadwaita GUI for the ClamAV antivirus scanner";
    homepage = "https://github.com/linx-systems/clamui";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "clamui";
  };
}
