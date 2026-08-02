{ config, lib, pkgs, ... }:

{
  services.tailscale.enable = true;

  # Habilita Tailscale SSH: los peers del tailnet pueden conectar por SSH
  # usando la identidad de Tailscale (ACLs del admin console), sin sshd de
  # NixOS ni claves SSH propias. `tailscale set --ssh` queda persistido en
  # el estado de tailscaled igual que el exit node (ver comentario abajo),
  # pero lo declaramos como extraUpFlags para que sobreviva un `tailscale up`
  # desde cero (ej. reinstalación) sin pasos manuales.
  services.tailscale.extraUpFlags = [ "--ssh" ];

  # mosh necesita SSH para el handshake inicial (lo cubre Tailscale SSH de
  # arriba) y después habla UDP en este rango de puertos.
  programs.mosh.enable = true;

  # Todo el tráfico entre peers del tailnet (SSH, mosh, etc.) llega por esta
  # interfaz -- confiamos en las ACLs de Tailscale en vez de duplicar reglas
  # de firewall locales por puerto.
  networking.firewall.trustedInterfaces = [ "tailscale0" ];

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
  # BUG real, corregido: en el 100% de los arranques este servicio fallaba
  # en el primer intento (`invalid value "mullvad-exit" for --exit-node;
  # must be IP or hostname`, visto en journalctl -p3) porque corría antes
  # de que tailscaled terminara de sincronizar el netmap -- sin el netmap
  # sincronizado, tailscaled no puede resolver el nombre "mullvad-exit" a
  # un peer. El `Restart = "on-failure"` de antes lo disimulaba (10s
  # después reintentaba y ya funcionaba), pero dejaba un "Failed to start"
  # real en el journal en cada boot. Ahora el propio ExecStart reintenta
  # el comando con backoff antes de darle a systemd un fallo real.
  systemd.services.tailscale-exit-node = {
    description = "Fijar exit node de Mullvad en Tailscale";
    after = [ "tailscaled.service" "network-online.target" ];
    wants = [ "tailscaled.service" "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "tailscale-exit-node" ''
        set -u
        for i in $(seq 1 10); do
          if ${pkgs.tailscale}/bin/tailscale set --exit-node=mullvad-exit --exit-node-allow-lan-access=true; then
            exit 0
          fi
          sleep 2
        done
        exit 1
      '';
      Restart = "on-failure";
      RestartSec = "10s";
    };
  };
}
