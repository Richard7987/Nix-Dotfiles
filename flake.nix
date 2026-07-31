{
  description = "Configuración NixOS de ale — Hyprland + Noctalia";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    noctalia = {
      url = "github:noctalia-dev/noctalia";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    noctalia-greeter = {
      url = "github:noctalia-dev/noctalia-greeter";
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
  };

  outputs =
    { self
    , nixpkgs
    , home-manager
    , noctalia
    , noctalia-greeter
    , zen-browser
    , gruvbox-wallpapers
    , psysonic
    , nezzontli-ctl
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
          # nixpkgs subió su propio módulo `programs.noctalia` (2026-07-29,
          # nixos/modules/programs/wayland/noctalia.nix) que choca con el
          # módulo del input noctalia (misma opción declarada dos veces).
          # Usamos el del input, que sigue el upstream de noctalia-dev.
          { disabledModules = [ "programs/wayland/noctalia.nix" ]; }
          ./hosts/ale/configuration.nix
          noctalia.nixosModules.default
          noctalia-greeter.nixosModules.default
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
