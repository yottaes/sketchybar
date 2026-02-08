local colors = require("colors")
local settings = require("settings")
local app_icons = require("app_icons")

-- Aerospace workspace: single active workspace pill + window app icons
-- Subscribes to aerospace_workspace_change and front_app_switched
-- All sbar.exec() calls use hardcoded strings with no user input.

sbar.add("event", "aerospace_workspace_change")

local MAX_WINDOW_ICONS = 10

-- Workspace ID pill (e.g. "Z" in lavender background)
local workspace_pill = sbar.add("item", "aerospace.workspace", {
  position = "left",
  icon = {
    font = {
      family = settings.font.numbers,
      style = settings.font.style_map["Bold"],
      size = 13.0,
    },
    string = "?",
    padding_left = 8,
    padding_right = 8,
    color = colors.base,
  },
  label = { drawing = false },
  padding_left = 2,
  padding_right = 2,
  background = {
    height = 22,
    corner_radius = 6,
    color = colors.lavender,
  },
})

-- Pre-create window icon items (hidden by default)
local window_icons = {}
for i = 1, MAX_WINDOW_ICONS do
  window_icons[i] = sbar.add("item", "aerospace.win." .. i, {
    position = "left",
    icon = {
      font = {
        family = "sketchybar-app-font",
        style = "Regular",
        size = 16.0,
      },
      string = "",
      color = colors.overlay0,
    },
    label = { drawing = false },
    drawing = false,
    padding_left = 1,
    padding_right = 1,
    background = { drawing = false },
  })
end

local function get_focused_workspace()
  local p = io.popen("aerospace list-workspaces --focused 2>/dev/null")
  if not p then return nil end
  local ws = p:read("*l")
  p:close()
  if ws then ws = ws:match("^%s*(.-)%s*$") end
  return (ws and ws ~= "") and ws or nil
end

local function get_workspace_windows()
  local windows = {}
  local p = io.popen("aerospace list-windows --workspace focused --format '%{app-name}' 2>/dev/null")
  if not p then return windows end
  for line in p:lines() do
    local app = line:match("^%s*(.-)%s*$")
    if app and app ~= "" then
      windows[#windows + 1] = app
    end
  end
  p:close()
  return windows
end

local function get_focused_app()
  local p = io.popen("aerospace list-windows --focused --format '%{app-name}' 2>/dev/null")
  if not p then return nil end
  local app = p:read("*l")
  p:close()
  if app then app = app:match("^%s*(.-)%s*$") end
  return (app and app ~= "") and app or nil
end

-- Initial display (blocking at startup is fine)
local function update_display_sync()
  local ws = get_focused_workspace()
  workspace_pill:set({ icon = { string = ws or "?" } })

  local windows = get_workspace_windows()
  local focused_app = get_focused_app()

  for i = 1, MAX_WINDOW_ICONS do
    local app = windows[i]
    if app then
      local icon_str = app_icons[app] or app_icons["Default"] or ":default:"
      local is_focused = (app == focused_app)
      window_icons[i]:set({
        drawing = true,
        icon = {
          string = icon_str,
          color = is_focused and colors.text or colors.overlay0,
        },
      })
    else
      window_icons[i]:set({ drawing = false })
    end
  end
end

-- Async update for event-driven callbacks (hardcoded commands, no user input)
local function update_display_async()
  if _G.SKETCHYBAR_SUSPENDED then return end

  sbar.exec("aerospace list-workspaces --focused 2>/dev/null", function(ws_out)
    local ws = tostring(ws_out or ""):match("^%s*(.-)%s*$")
    if ws == "" then ws = "?" end
    workspace_pill:set({ icon = { string = ws } })

    sbar.exec("aerospace list-windows --workspace focused --format '%{app-name}' 2>/dev/null", function(win_out)
      local win_text = tostring(win_out or "")
      local windows = {}
      for line in win_text:gmatch("[^\r\n]+") do
        local app = line:match("^%s*(.-)%s*$")
        if app and app ~= "" then
          windows[#windows + 1] = app
        end
      end

      sbar.exec("aerospace list-windows --focused --format '%{app-name}' 2>/dev/null", function(focused_out)
        local focused_app = tostring(focused_out or ""):match("^%s*(.-)%s*$")
        if focused_app == "" then focused_app = nil end

        for i = 1, MAX_WINDOW_ICONS do
          local app = windows[i]
          if app then
            local icon_str = app_icons[app] or app_icons["Default"] or ":default:"
            local is_focused = (app == focused_app)
            window_icons[i]:set({
              drawing = true,
              icon = {
                string = icon_str,
                color = is_focused and colors.text or colors.overlay0,
              },
            })
          else
            window_icons[i]:set({ drawing = false })
          end
        end
      end)
    end)
  end)
end

update_display_sync()

workspace_pill:subscribe("aerospace_workspace_change", function(_)
  update_display_async()
end)

workspace_pill:subscribe("front_app_switched", function(_)
  update_display_async()
end)
