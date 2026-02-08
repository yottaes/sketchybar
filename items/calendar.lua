local settings = require("settings")
local colors = require("colors")

-- Date/time widget (no icon, clean text only)

local last_label = nil

local cal = sbar.add("item", "widgets.calendar", {
  position = "right",
  icon = { drawing = false },
  label = {
    font = {
      family = settings.font.numbers,
      style = settings.font.style_map["Semibold"],
      size = 13.0,
    },
    color = colors.text,
    padding_left = 6,
    padding_right = 6,
    string = "Loading...",
  },
  padding_left = 0,
  padding_right = 0,
  update_freq = 30,
})

local function update_calendar()
  if _G.SKETCHYBAR_SUSPENDED then return end
  local label = os.date("%a %b %d  %H:%M")
  if last_label == label then return end
  last_label = label
  cal:set({ label = { string = label } })
end

cal:subscribe({ "forced", "routine", "system_woke" }, update_calendar)
update_calendar()

-- Click opens notification center (hardcoded osascript, no user input)
cal:subscribe("mouse.clicked", function(env)
  if env.BUTTON ~= "left" then return end
  sbar.exec('osascript -e ' .. "'" .. 'tell application "System Events" to click menu bar item 1 of menu bar 1 of application process "ControlCenter"' .. "'" .. ' >/dev/null 2>&1')
end)
