{ config, lib, pkgs, ... }:

{
  # pcscd + udev rules para que el sistema vea la YubiKey como smartcard.
  # A diferencia de FreeBSD, en NixOS/Linux no hace falta --disable-polkit ni
  # disable-ccid por defecto: aquí polkit funciona bien. Si algún día ves el
  # mismo error "not authorized for action: access_pcsc" que en FreeBSD,
  # revisa `polkit` y los grupos del usuario antes de copiar ese workaround.
  services.pcscd.enable = true;
  services.udev.packages = with pkgs; [ yubikey-personalization ];

  environment.systemPackages = with pkgs; [
    yubikey-manager # ykman
    yubikey-personalization
    gnupg
  ];

  # sudo (a pedido explícito para esta config de NixOS -- distinto de FreeBSD,
  # donde se usa doas; ver memoria user_prefs / nixos_migration).
  # `ale` ya está en el grupo "wheel" (hosts/ale/configuration.nix), lo que le
  # da acceso root completo con contraseña vía las reglas por defecto del
  # módulo (security.sudo.wheelNeedsPassword = true por defecto) -- no hace
  # falta una regla general aparte. Solo agregamos las dos excepciones sin
  # contraseña que sí tenías en FreeBSD (equivalente doas nopass).
  security.sudo = {
    enable = true;
    # mkAfter: la doc de la opción indica explícitamente usar mkBefore/mkAfter
    # para controlar el orden relativo a las reglas por defecto del módulo
    # ("More specific rules should come after more general ones... You can
    # use mkBefore and/or mkAfter to ensure this is the case").
    extraRules = lib.mkAfter [
      {
        # Reiniciar pcscd sin contraseña, para que el comando `yubico`
        # (definido en home/ale/home.nix) sea instantáneo. Ruta absoluta:
        # sudoers matchea por ruta resuelta, no por nombre en $PATH.
        users = [ "ale" ];
        commands = [
          {
            command = "/run/current-system/sw/bin/systemctl restart pcscd.service";
            options = [ "NOPASSWD" ];
          }
        ];
      }
      {
        # Igual que en FreeBSD: tailscale sin contraseña ni TTY (para el popup
        # GUI). Sin argumentos en el comando = cualquier argumento permitido
        # (semántica de sudoers, al revés que en doas donde "sin args" = "sin
        # restricción" se logra con `args = null` y no con una ruta pelada).
        users = [ "ale" ];
        commands = [
          {
            command = "/run/current-system/sw/bin/tailscale";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];
  };
}
