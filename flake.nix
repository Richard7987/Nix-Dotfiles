{
  description = "Configuración NixOS de ale — niri + DankMaterialShell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Solo se usan los módulos NixOS/home-manager del propio flake
    # (programs.dank-material-shell.*), NO su módulo `niri` (distro/nix/niri.nix
    # exige sodiboo/niri-flake, que no se agrega -- el config.kdl se escribe a
    # mano contra el módulo `programs.niri` que ya trae nixpkgs).
    #
    # Pineado al tag v1.5.3 (la MISMA versión que usa pkgs.dms-shell de
    # nixpkgs) a propósito, NO la rama main -- diagnosticado en vivo
    # (2026-08-10, ver NOTES.md, Fase 3): sin pin, este input flotaba en un
    # commit de main post-1.5.3 ("1.6-beta") que ya había reestructurado
    # Modules/Greetd/ (movido a Modals/Greeter/, sin el launcher
    # Modules/Greetd/assets/dms-greeter). services.displayManager.dms-greeter
    # (nixos/modules/services/display-managers/dms-greeter.nix de nixpkgs)
    # tiene esa ruta hardcodeada -- greetd fallaba al arrancar la sesión
    # ("No existe el fichero o el directorio") en cuanto se reinició con
    # dms-greeter activo. v1.5.3 es además el último tag publicado (no hay
    # v1.6 todavía, confirmado con `git ls-remote --tags`).
    dank-material-shell = {
      url = "github:AvengeMedia/DankMaterialShell/v1.5.3";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # DankCalendar (dcal): sync CalDAV/Nextcloud/Google/etc. para el widget de
    # calendario de DMS -- vía módulo home-manager propio del flake, no hay
    # paquete en nixpkgs (ver home/ale/home.nix, programs.dank-calendar).
    dankcalendar = {
      url = "github:AvengeMedia/dankcalendar";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    psysonic = {
      url = "github:Psychotoxical/psysonic";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # TUI para crear/editar contenido de nezzontli.xyz sin CMS externo (no
    # soportan git-lfs, que es como se versionan las fotos). Canónico en
    # Forgejo (Tailscale-only); este input usa el mirror de GitHub para que
    # nixos-rebuild funcione también fuera de la red de Tailscale.
    nezzontli-ctl = {
      url = "github:Richard7987/nezzontli-ctl";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Wallpapers estilo Gruvbox (paquete Nix real, no archivos sueltos —
    # ver home/ale/home.nix para cómo se instala vía home.file).
    gruvbox-wallpapers = {
      url = "github:AngelJumbo/gruvbox-wallpapers";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Fork personal de maaslalani/slides (presentador de terminal) con
    # LaTeX, imágenes reales y bibliografía vía Kitty Graphics Protocol.
    # Canónico en el remoto Tailscale-only de este equipo; este input usa
    # el mirror de GitHub (mismo criterio que nezzontli-ctl) para que
    # nixos-rebuild funcione también fuera de la red de Tailscale.
    slides = {
      url = "github:Richard7987/slide";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self
    , nixpkgs
    , home-manager
    , dank-material-shell
    , dankcalendar
    , zen-browser
    , gruvbox-wallpapers
    , psysonic
    , nezzontli-ctl
    , slides
    , ...
    }@inputs:
    let
      system = "x86_64-linux";
    in
    {
      nixosConfigurations.ale = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [
          ./hosts/ale/configuration.nix
          dank-material-shell.nixosModules.default
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "hm-backup"; # evita que un archivo preexistente tumbe la activación
            home-manager.extraSpecialArgs = { inherit inputs; };
            home-manager.users.ale = import ./home/ale/home.nix;
          }
        ];
      };
    };
}
