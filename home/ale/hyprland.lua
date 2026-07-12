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

-- Monitores: "auto" funciona para empezar. Si tienes más de un monitor o
-- quieres posiciones/resoluciones fijas, agrega una línea hl.monitor() por
-- cada salida (hyprctl monitors te da los nombres, ej. "eDP-1", "DP-1").
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })

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

  gestures = {
    workspace_swipe = true,
  },
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
  match = { namespace = "^noctalia-(bar-.+|notification|dock|panel|attached-panel|osd)$" },
  blur = true,
  blur_popups = true,
  ignore_alpha = 0.5,
})

-- --- Apps / básicos ---
hl.bind(mainMod .. "+Return", hl.dsp.exec_cmd("kitty")) -- AJUSTAR si usas otra terminal
hl.bind(mainMod .. "+B", hl.dsp.exec_cmd("zen-beta")) -- canal "default" del flake = beta -> binario zen-beta
hl.bind(mainMod .. "+Q", hl.dsp.window.close())
hl.bind(mainMod .. "+F", hl.dsp.window.fullscreen())
hl.bind(mainMod .. "+V", hl.dsp.window.float({ action = "toggle" }))

-- --- Atajos de Noctalia (launcher / control center / settings) ---
-- La doc de Noctalia lista estos atajos (mainMod+Space, mainMod+S, mainMod+,)
-- como parte de su integración con Hyprland, pero no publica el comando IPC
-- exacto detrás de cada uno. Es muy probable que Noctalia los registre solo
-- al arrancar (junto con hl.exec_cmd("noctalia") de arriba) y no necesites
-- definir nada aquí. Deja estas líneas comentadas y solo actívalas /
-- corrígelas si al probar ves que Noctalia NO trae sus propios keybinds:
--
-- hl.bind(mainMod .. "+Space", hl.dsp.exec_cmd("noctalia-shell ipc call launcher toggle"))
-- hl.bind(mainMod .. "+S", hl.dsp.exec_cmd("noctalia-shell ipc call control_center toggle"))
-- hl.bind(mainMod .. ",", hl.dsp.exec_cmd("noctalia-shell ipc call settings toggle"))

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

-- --- Teclas multimedia ---
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"))
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"))
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"))
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl set +5%"))
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl set 5%-"))
