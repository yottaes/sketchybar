local colors = require("colors")
local settings = require("settings")

-- Aerospace workspace indicators (replaces macOS native spaces)
-- Subscribes to aerospace_workspace_change custom event

sbar.add("event", "aerospace_workspace_change")

local spaces = {}

-- Get workspace list from aerospace
local p = io.popen("aerospace list-workspaces --all 2>/dev/null")
local workspace_ids = {}
if p then
  for line in p:lines() do
    local id = line:match("^%s*(.-)%s*$")
    if id and id ~= "" then
      workspace_ids[#workspace_ids + 1] = id
    end
  end
  p:close()
end

-- Fallback if aerospace isn't running
if #workspace_ids == 0 then
  workspace_ids = { "1", "2", "F", "4", "5", "Z", "R", "D", "S", "T", "G", "M", "H", "J" }
end

-- Get the currently focused workspace
local focused_p = io.popen("aerospace list-workspaces --focused 2>/dev/null")
local focused_workspace = nil
if focused_p then
  focused_workspace = focused_p:read("*l")
  if focused_workspace then
    focused_workspace = focused_workspace:match("^%s*(.-)%s*$")
  end
  focused_p:close()
end

for _, sid in ipairs(workspace_ids) do
  local is_focused = (sid == focused_workspace)
  local space = sbar.add("item", "space." .. sid, {
    icon = {
      font = {
        family = settings.font.numbers,
        style = settings.font.style_map["Bold"],
        size = 13.0,
      },
      string = sid,
      padding_left = 8,
      padding_right = 8,
      color = is_focused and colors.base or colors.subtext0,
    },
    label = { drawing = false },
    padding_left = 2,
    padding_right = 2,
    background = {
      height = 22,
      corner_radius = 6,
      color = is_focused and colors.lavender or colors.transparent,
    },
    click_script = "aerospace workspace " .. sid,
  })

  spaces[sid] = space

  space:subscribe("aerospace_workspace_change", function(env)
    local focused = env.FOCUSED_WORKSPACE
    local selected = (focused == sid)
    space:set({
      icon = { color = selected and colors.base or colors.subtext0 },
      background = { color = selected and colors.lavender or colors.transparent },
    })
  end)
end
