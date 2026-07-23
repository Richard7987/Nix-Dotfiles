-- ~/.config/hypr/hyprland.lua
-- Config de Hyprland (API Lua, Hyprland >= 0.55) + integración con Noctalia.
-- Docs: https://wiki.hypr.land/  y  https://docs.noctalia.dev/v5/compositor-settings/hyprland/
--
-- NOTA: solo queda pendiente el nombre real del monitor (bloques marcados
-- "AJUSTAR" más abajo) — eso depende del hardware real y no lo puedo
-- detectar desde aquí. Usa `hyprctl monitors` una vez instalado.
-- Terminal (kitty), teclado (us+altgr-intl) y navegador (zen-beta) ya están
-- resueltos.

local mainMod = "SUPER"

-- Monitores: eDP-1 es un panel 1920x1080 de 15.3" (~144 PPI) -- no es HiDPI,
-- así que se fija scale=1 en vez de dejar "auto" (que Hyprland resolvía a
-- 1.5, reduciendo el espacio lógico a 1280x720 y amontonando el dock de
-- Noctalia / agrandando las ventanas). Si agregas más monitores, una línea
-- hl.monitor() por cada salida (hyprctl monitors te da los nombres).
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "1" })

hl.config({
  input = {
    kb_layout = "us",
    kb_variant = "altgr-intl", -- US con AltGr para acentos/ñ: AltGr+n = ñ, AltGr+' luego vocal = tilde
    follow_mouse = 1,
    sensitivity = 0,
    touchpad = { natural_scroll = true },
  },

  general = {
    gaps_in = 5,
    gaps_out = 10,
    border_size = 2,
    layout = "dwindle",
  },

  -- Valores tomados directo de la doc de Noctalia para que los efectos de
  -- blur/sombra combinen bien con el shell.
  decoration = {
    rounding = 20,
    rounding_power = 2,
    shadow = {
      enabled = true,
      range = 4,
      render_power = 3,
      color = 0xee1a1a1a,
    },
    blur = {
      enabled = true,
      size = 3,
      passes = 2,
      vibrancy = 0.1696,
    },
  },

  animations = {
    enabled = true,
  },
})

-- Hyprland >= 0.51 reemplazó el viejo `gestures:workspace_swipe` (booleano)
-- por este sistema de gestos configurables por dedos/dirección/acción.
hl.gesture({
  fingers = 3,
  direction = "horizontal",
  action = "workspace",
})

-- Lanza Noctalia (barra, panel, control center, OSD...) al arrancar Hyprland
hl.on("hyprland.start", function()
  hl.exec_cmd("noctalia")
end)

-- Espacios de trabajo persistentes (1-5, siempre visibles aunque estén vacíos)
-- AJUSTAR "eDP-1" al nombre real de tu monitor principal (hyprctl monitors)
for i = 1, 5 do
  hl.workspace_rule({ workspace = tostring(i), monitor = "eDP-1", persistent = true })
end

-- Blur y sin animaciones para las superficies de Noctalia (barra, notificaciones,
-- dock, panel, OSD) — regla tal cual la documenta Noctalia
hl.layer_rule({
  name = "noctalia",
  match = { namespace = "^noctalia-(bar-.+|notification|dock|panel|attached-panel|osd)$" },
  no_anim = true,
  blur = true,
  blur_popups = true,
  ignore_alpha = 0.5,
})

-- Ventana de ajustes de Noctalia: flotante y con tamaño fijo (tal cual la
-- documenta Noctalia) en vez de tiling como cualquier otra ventana.
hl.window_rule({
  match = { class = "dev.noctalia.Noctalia" },
  float = true,
  size = { 1080, 920 },
})

-- --- Apps / básicos ---
hl.bind(mainMod .. "+Return", hl.dsp.exec_cmd("kitty")) -- AJUSTAR si usas otra terminal
hl.bind(mainMod .. "+B", hl.dsp.exec_cmd("zen-beta")) -- canal "default" del flake = beta -> binario zen-beta
hl.bind(mainMod .. "+Q", hl.dsp.window.close())
hl.bind(mainMod .. "+F", hl.dsp.window.fullscreen())
hl.bind(mainMod .. "+V", hl.dsp.window.float({ action = "toggle" }))

-- --- Atajos de Noctalia (launcher / control center / settings) ---
-- Comando IPC real confirmado contra docs.noctalia.dev/v5/compositor-settings/hyprland
-- (la incertidumbre de rondas de auditoría anteriores -- "noctalia-shell ipc
-- call ... toggle" -- era un nombre inventado; el real es "noctalia msg ...").
local noctaliaMsg = "noctalia msg "
hl.bind(mainMod .. "+Space", hl.dsp.exec_cmd(noctaliaMsg .. "panel-toggle launcher"))
hl.bind(mainMod .. "+S", hl.dsp.exec_cmd(noctaliaMsg .. "panel-toggle control-center"))
hl.bind(mainMod .. "+comma", hl.dsp.exec_cmd(noctaliaMsg .. "settings-toggle"))
hl.bind(mainMod .. "+L", hl.dsp.exec_cmd(noctaliaMsg .. "session lock"))

-- --- Navegación de foco ---
hl.bind(mainMod .. "+Left", hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. "+Right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. "+Up", hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. "+Down", hl.dsp.focus({ direction = "down" }))

-- --- Workspaces 1-9 ---
-- (exec_raw es para lanzar programas sin comillas de shell, NO para dispatchers
-- de compositor -- el cambio de workspace va por hl.dsp.focus/window.move)
for i = 1, 9 do
  hl.bind(mainMod .. "+" .. i, hl.dsp.focus({ workspace = tostring(i) }))
  hl.bind(mainMod .. "+SHIFT+" .. i, hl.dsp.window.move({ workspace = tostring(i) }))
end

-- Meta + rueda del mouse = workspace siguiente/anterior (relativo, "e+1"/"e-1").
-- Sintaxis tomada del hyprland.lua de ejemplo que trae el propio paquete
-- (/run/current-system/sw/share/hypr/hyprland.lua), no hay doc separada de
-- mouse_down/mouse_up en la wiki.
hl.bind(mainMod .. "+mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. "+mouse_up", hl.dsp.focus({ workspace = "e-1" }))

-- --- Teclas multimedia ---
-- Vía IPC de Noctalia (no wpctl/brightnessctl directo) para que el OSD de
-- volumen/brillo del shell se muestre en pantalla -- tal cual lo documenta
-- Noctalia para Hyprland.
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd(noctaliaMsg .. "volume-up"))
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd(noctaliaMsg .. "volume-down"))
hl.bind("XF86AudioMute", hl.dsp.exec_cmd(noctaliaMsg .. "volume-mute"))
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd(noctaliaMsg .. "brightness-up"))
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd(noctaliaMsg .. "brightness-down"))

-- Colores de borde de ventana generados por Noctalia (~/.config/hypr/noctalia.lua,
-- regenerado en cada cambio de theme por el template built-in "hyprland").
-- Normalmente el propio Noctalia agrega este require automáticamente (vía su
-- assets/templates/hyprland/apply.sh), pero como hyprland.lua acá es un
-- symlink de solo lectura al store de Nix (gestionado por home-manager),
-- Noctalia no puede escribirlo -- por eso se declara a mano, una sola vez.
-- pcall: en una instalación nueva, este archivo no existe todavía en el
-- primer arranque (antes de que Noctalia corra y lo genere) -- sin esto,
-- Hyprland fallaría al parsear el resto del archivo ese primer boot.
pcall(function() require("noctalia").apply_theme() end)
