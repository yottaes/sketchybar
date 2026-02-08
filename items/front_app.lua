local colors = require("colors")
local settings = require("settings")
local app_icons = require("app_icons")

-- Front app indicator showing the current app name + icon
local front_app = sbar.add("item", "widgets.front_app", {
  position = "left",
  icon = {
    font = {
      family = "sketchybar-app-font",
      style = "Regular",
      size = 16.0,
    },
    string = app_icons["Default"] or ":default:",
    color = colors.text,
  },
  label = {
    font = {
      family = settings.font.text,
      style = settings.font.style_map["Semibold"],
      size = 13.0,
    },
    color = colors.text,
    max_chars = 20,
  },
  padding_left = 4,
  padding_right = 4,
  background = { drawing = false },
})

front_app:subscribe("front_app_switched", function(env)
  local app = env.INFO or ""
  local icon = app_icons[app] or app_icons["Default"] or ":default:"
  front_app:set({
    icon = { string = icon },
    label = { string = app },
  })
end)
