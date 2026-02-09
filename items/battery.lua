local icons = require("icons")
local colors = require("colors")
local settings = require("settings")

-- Battery widget (no popup). Click opens System Preferences.
-- Background maintain-charge logic is preserved.
-- NOTE: sbar.exec is the SketchyBar Lua API, NOT Node.js child_process.
-- All commands below are hardcoded paths to local helper binaries.

local config_path = os.getenv("HOME") .. "/.config/sketchybar"
local state_file = config_path .. "/states/battery_control.lua"
local battery_helper_path = config_path .. "/helpers/battery_info/bin/battery_info"
local battery_control_path = config_path .. "/helpers/battery_control/bin/battery_control"

local last_charge = nil
local last_charging = nil
local last_icon = nil
local last_color = nil

local maintain_state = {
  enabled = false,
  target = 80,
  history = {},
}

local function load_state()
  local f = io.open(state_file, "r")
  if not f then return end
  local content = f:read("*a")
  f:close()
  local fn = load("return " .. content)
  if fn then
    local ok, loaded = pcall(fn)
    if ok and type(loaded) == "table" then
      if loaded.target then maintain_state.target = loaded.target end
      if loaded.enabled ~= nil then maintain_state.enabled = loaded.enabled end
      if loaded.history then maintain_state.history = loaded.history end
    end
  end
end

local function serialize(t, indent)
  indent = indent or ""
  local parts = {}
  parts[#parts + 1] = "{"
  local next_indent = indent .. "  "
  for k, v in pairs(t) do
    local key_str
    if type(k) == "number" then
      key_str = ""
    else
      key_str = k .. " = "
    end
    local val_str
    if type(v) == "table" then
      val_str = serialize(v, next_indent)
    elseif type(v) == "string" then
      val_str = string.format("%q", v)
    elseif type(v) == "boolean" then
      val_str = v and "true" or "false"
    else
      val_str = tostring(v)
    end
    parts[#parts + 1] = next_indent .. key_str .. val_str .. ","
  end
  parts[#parts + 1] = indent .. "}"
  return table.concat(parts, "\n")
end

local function save_state()
  local f = io.open(state_file, "w")
  if not f then return end
  f:write(serialize(maintain_state))
  f:close()
end

local function record_history(percent)
  table.insert(maintain_state.history, percent)
  while #maintain_state.history > 144 do
    table.remove(maintain_state.history, 1)
  end
  save_state()
end

load_state()

local function file_exists(path)
  local f = io.open(path, "r")
  if not f then return false end
  f:close()
  return true
end

local function fetch_battery_info(callback)
  if not file_exists(battery_helper_path) then
    if callback then callback(nil, 1) end
    return
  end
  -- Hardcoded path to local helper binary
  sbar.exec(battery_helper_path, function(info, exit_code)
    if callback then callback(info, exit_code) end
  end)
end

local function enable_charging(callback)
  -- Hardcoded path to local helper binary
  sbar.exec("sudo " .. battery_control_path .. " enable", function(_, exit_code)
    if callback then callback(exit_code == 0) end
  end)
end

local function disable_charging(callback)
  -- Hardcoded path to local helper binary
  sbar.exec("sudo " .. battery_control_path .. " disable", function(_, exit_code)
    if callback then callback(exit_code == 0) end
  end)
end

local function enable_adapter(callback)
  -- Hardcoded path to local helper binary
  sbar.exec("sudo " .. battery_control_path .. " adapter off", function(_, exit_code)
    if callback then callback(exit_code == 0) end
  end)
end

local battery = sbar.add("item", "widgets.battery", {
  position = "right",
  icon = {
    font = {
      style = settings.font.style_map["Regular"],
      size = 15.0,
    }
  },
  label = {
    font = { family = settings.font.numbers },
    width = 32,
    padding_left = 2,
    padding_right = 6,
  },
  padding_left = 0,
  padding_right = 0,
  update_freq = 600,
})

local function update_battery()
  if _G.SKETCHYBAR_SUSPENDED then return end
  fetch_battery_info(function(info, exit_code)
    if exit_code ~= 0 or type(info) ~= "table" then return end
    local charge = tonumber(info.percent)
    if not charge then return end
    local charge_i = math.floor(charge + 0.5)
    local charging = info.is_charging == true
    local charged = info.is_charged == true

    local color = colors.green
    local icon = icons.battery._0
    if charging then
      icon = icons.battery.charging
    elseif charged then
      icon = icons.battery._100
    else
      if charge > 80 then icon = icons.battery._100
      elseif charge > 60 then icon = icons.battery._75
      elseif charge > 40 then icon = icons.battery._50
      elseif charge > 20 then icon = icons.battery._25; color = colors.peach
      else icon = icons.battery._0; color = colors.red end
    end

    if last_charge == charge_i and last_charging == charging and last_icon == icon and last_color == color then return end
    last_charge = charge_i
    last_charging = charging
    last_icon = icon
    last_color = color
    battery:set({ icon = { string = icon, color = color }, label = { string = tostring(charge_i) } })
  end)
end

local MAINTAIN_HYSTERESIS = 2

local function check_and_maintain()
  if not maintain_state.enabled then return end
  if not file_exists(battery_control_path) then return end
  fetch_battery_info(function(info, exit_code)
    if exit_code ~= 0 or type(info) ~= "table" then return end
    local percent = tonumber(info.percent)
    if not percent then return end
    -- Hardcoded path to local helper binary
    sbar.exec("sudo " .. battery_control_path .. " status", function(ctrl_info, ctrl_exit)
      if ctrl_exit ~= 0 or type(ctrl_info) ~= "table" then return end
      local charging_enabled = ctrl_info.charging_enabled
      if percent >= maintain_state.target then
        if charging_enabled then disable_charging(function() end) end
      elseif percent < maintain_state.target - MAINTAIN_HYSTERESIS then
        if not charging_enabled then
          enable_adapter(function() enable_charging(function() end) end)
        end
      end
    end)
  end)
end

local history_counter = 0
local function routine_update()
  check_and_maintain()
  history_counter = history_counter + 1
  if history_counter >= 10 then
    history_counter = 0
    fetch_battery_info(function(info, exit_code)
      if exit_code ~= 0 or type(info) ~= "table" then return end
      local percent = tonumber(info.percent)
      if percent then record_history(percent) end
    end)
  end
end

battery:subscribe({ "forced", "routine", "power_source_change", "system_woke" }, function()
  update_battery()
  routine_update()
end)
update_battery()

-- Click opens Battery preferences (hardcoded system URL)
battery:subscribe("mouse.clicked", function(env)
  if env.BUTTON ~= "left" and env.BUTTON ~= "right" then return end
  sbar.exec("/usr/bin/open 'x-apple.systempreferences:com.apple.preference.battery' >/dev/null 2>&1", function() end)
end)
