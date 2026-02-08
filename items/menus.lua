local settings = require("settings")

-- App menu bar items (reads native menu titles via helpers/menus binary).
-- All sbar.exec calls reference $CONFIG_DIR paths (SketchyBar Lua API, not Node.js).

local menu_watcher = sbar.add("item", "menus.watcher", {
  drawing = false,
  updates = true,
})

local SWITCH_DEBOUNCE_S = 0.45
local MENU_ITEM_GAP = 2
local MENU_LABEL_PADDING = 6

local max_items = 15
local menu_items = {}
for i = 1, max_items, 1 do
  local menu = sbar.add("item", "menu." .. i, {
    padding_left = MENU_ITEM_GAP,
    padding_right = MENU_ITEM_GAP,
    drawing = false,
    icon = { drawing = false, width = 0 },
    label = {
      font = { family = settings.font.text, size = 14.0 },
      padding_left = MENU_LABEL_PADDING,
      padding_right = MENU_LABEL_PADDING,
    },
    background = { drawing = false },
    click_script = "$CONFIG_DIR/helpers/menus/bin/menus -s " .. i,
  })
  menu_items[i] = menu
end

sbar.add("bracket", "menus.bracket", { '/menu\\..*/' }, {
  background = { drawing = false },
})

local menu_padding = sbar.add("item", "menu.padding", {
  drawing = false,
  width = settings.group_paddings,
})

local MAX_UPDATE_RETRIES = 4
local RETRY_BASE_DELAY_S = 0.20
local SUSPEND_RETRY_DELAY_S = 0.25

local last_rendered_menu_app = ""
local request_token = 0
local debounce_id = 0
local timer_armed = false

local function trim(s)
  return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function first_menu_title(menus)
  for menu_title in string.gmatch(menus or "", "[^\r\n]+") do
    menu_title = trim(menu_title)
    if menu_title ~= "" then return menu_title end
  end
  return ""
end

local function render_menus(menus)
  sbar.set('/menu\\..*/', { drawing = false })
  menu_padding:set({ drawing = true })
  local id = 1
  for menu_title in string.gmatch(menus or "", "[^\r\n]+") do
    menu_title = trim(menu_title)
    if menu_title ~= "" then
      if id <= max_items then
        menu_items[id]:set({ label = menu_title, drawing = true })
        id = id + 1
      else break end
    end
  end
end

local function retry_delay(attempt)
  return RETRY_BASE_DELAY_S * (attempt + 1)
end

-- Hardcoded path to menus helper binary
local menus_list_cmd = "$CONFIG_DIR/helpers/menus/bin/menus -l"

local function update_menus_with_retries(token, expects_change, baseline_menu_app, attempt)
  if token ~= request_token then return end
  if _G.SKETCHYBAR_SUSPENDED then
    sbar.delay(SUSPEND_RETRY_DELAY_S, function()
      update_menus_with_retries(token, expects_change, baseline_menu_app, attempt)
    end)
    return
  end

  sbar.exec(menus_list_cmd, function(menus, exit_code)
    if token ~= request_token then return end
    if _G.SKETCHYBAR_SUSPENDED then
      if attempt < MAX_UPDATE_RETRIES then
        sbar.delay(SUSPEND_RETRY_DELAY_S, function()
          update_menus_with_retries(token, expects_change, baseline_menu_app, attempt + 1)
        end)
      end
      return
    end
    if tonumber(exit_code) ~= 0 then
      if attempt < MAX_UPDATE_RETRIES then
        sbar.delay(retry_delay(attempt), function()
          update_menus_with_retries(token, expects_change, baseline_menu_app, attempt + 1)
        end)
      end
      return
    end
    local menu_app = first_menu_title(menus)
    if menu_app == "" or menu_app == "Dock" then
      if attempt < MAX_UPDATE_RETRIES then
        sbar.delay(retry_delay(attempt), function()
          update_menus_with_retries(token, expects_change, baseline_menu_app, attempt + 1)
        end)
      end
      return
    end
    if expects_change and menu_app == baseline_menu_app then
      if attempt < MAX_UPDATE_RETRIES then
        sbar.delay(retry_delay(attempt), function()
          update_menus_with_retries(token, expects_change, baseline_menu_app, attempt + 1)
        end)
      end
      return
    end
    render_menus(menus)
    last_rendered_menu_app = menu_app
  end)
end

local function request_update(expects_change)
  local baseline_menu_app = last_rendered_menu_app
  request_token = request_token + 1
  local token = request_token
  update_menus_with_retries(token, expects_change == true, baseline_menu_app, 0)
end

local function schedule_update_menus(_)
  debounce_id = debounce_id + 1
  local id = debounce_id
  if timer_armed then return end
  timer_armed = true
  sbar.delay(SWITCH_DEBOUNCE_S, function()
    timer_armed = false
    if id ~= debounce_id then schedule_update_menus(); return end
    request_update(true)
  end)
end

menu_watcher:subscribe("front_app_switched", schedule_update_menus)
sbar.delay(0.1, function() request_update(false) end)

return menu_watcher
