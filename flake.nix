{
  description = "Configuración NixOS de ale — Hyprland + Noctalia";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # SOLO para paquetes puntuales que no necesitan estar en la punta de
    # unstable y sí se benefician de builds de Hydra más estables/cacheados
    # (ver home/ale/home.nix, pkgsStable.sage) -- el resto del sistema
    # (Hyprland, Noctalia, zen-browser, el driver Nvidia) sigue en
    # nixpkgs/unstable arriba, sin tocar.
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-26.05";

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

    # Wallpapers estilo Gruvbox (paquete Nix real, no archivos sueltos —
    # ver home/ale/home.nix para cómo se instala vía home.file).
    gruvbox-wallpapers = {
      url = "github:AngelJumbo/gruvbox-wallpapers";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # LazyVim declarativo -- la config en sí (autocmds/keymaps/options/specs
    # de plugins) queda versionada acá, pero lazy.nvim (el package manager
    # propio de LazyVim) sigue administrando la instalación/actualización
    # de los plugins por su cuenta -- es el híbrido que recomienda la
    # comunidad en vez de nixificar cada plugin individualmente (mucha
    # fricción con las actualizaciones de otra forma).
    lazyvim = {
      url = "github:pfassina/lazyvim-nix";
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
