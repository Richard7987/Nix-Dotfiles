{ config, lib, pkgs, ... }:

{
  services.tailscale.enable = true;

  # Recomendado por Tailscale cuando usas exit nodes / subnet routes
  networking.firewall.checkReversePath = "loose";

  # La primera vez tienes que autenticar a mano:
  #   sudo tailscale up
  # (se abre el flujo de login en el navegador; una sola vez).
  #
  # Una vez logueado, `tailscale set --exit-node=...` queda persistido en el
  # estado de tailscaled y se reaplica solo en cada arranque — no depende de
  # que inicies sesión gráfica. Este servicio systemd solo existe para dejarlo
  # explícito y reintentar si por lo que sea falla la primera vez (ej. arrancó
  # antes de que hubiera red). Esto reemplaza el paso manual
  # `doas tailscale set --exit-node=mullvad-exit` que hacías en FreeBSD (aquí
  # usamos sudo, no doas -- ver modules/yubikey.nix), y no depende del bug del
  # driver wifi que tenías ahí (ver memoria freebsd_wifi_boot_stall) — en esta
  # máquina no debería repetirse.
  systemd.services.tailscale-exit-node = {
    description = "Fijar exit node de Mullvad en Tailscale";
    after = [ "tailscaled.service" "network-online.target" ];
    wants = [ "tailscaled.service" "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.tailscale}/bin/tailscale set --exit-node=mullvad-exit --exit-node-allow-lan-access=true";
      Restart = "on-failure";
      RestartSec = "10s";
    };
  };
}
