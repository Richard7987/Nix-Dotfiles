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

  # doas en vez de sudo (preferencia del usuario, igual que en FreeBSD)
  security.doas = {
    enable = true;
    extraRules = [
      {
        # Regla general: pide contraseña una vez y la recuerda un rato (persist)
        users = [ "ale" ];
        keepEnv = true;
        persist = true;
      }
      {
        # Reiniciar pcscd sin contraseña, para que el comando `yubico`
        # (definido en home/ale/home.nix) sea instantáneo
        users = [ "ale" ];
        noPass = true;
        cmd = "systemctl";
        args = [ "restart" "pcscd.service" ];
      }
      {
        # Igual que en FreeBSD: tailscale sin contraseña ni TTY (para el popup GUI)
        users = [ "ale" ];
        noPass = true;
        cmd = "tailscale";
      }
    ];
  };
  # Se deja sudo disponible por compatibilidad con herramientas que lo esperen;
  # el uso diario es con doas.
  security.sudo.enable = lib.mkDefault true;
}
