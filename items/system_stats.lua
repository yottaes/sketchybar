local colors = require("colors")
local settings = require("settings")
local center_popup = require("center_popup")

-- Launch native system_stats helper (CPU/GPU/temp/memory event provider)
-- NOTE: sbar.exec is the SketchyBar Lua API (not Node.js); all commands are hardcoded
sbar.exec("killall system_stats >/dev/null 2>&1; " .. os.getenv("CONFIG_DIR") .. "/helpers/system_stats/bin/system_stats system_stats_update 2.0")

local graph_width = 80

local function make_graph(name, icon_text, graph_color, padding_right)
  return sbar.add("graph", name, graph_width, {
    position = "right",
    graph = { color = colors.with_alpha(graph_color, 0.4) },
    icon = {
      string = icon_text,
      color = graph_color,
      font = {
        family = settings.font.text,
        style = settings.font.style_map["Heavy"],
        size = 12.0,
      },
      padding_left = 4,
      padding_right = 0,
    },
    label = {
      string = "--",
      color = colors.text,
      font = {
        family = settings.font.numbers,
        style = settings.font.style_map["Bold"],
        size = 9.0,
      },
      align = "right",
      padding_left = 2,
      padding_right = 6,
      width = 0,
      y_offset = 4,
    },
    padding_left = 0,
    padding_right = padding_right or 0,
  })
end

local trailing_gap = 16
local mem = make_graph("widgets.sys.mem", "MEM", colors.teal, trailing_gap)
local gpu = make_graph("widgets.sys.gpu", "GPU", colors.mauve, 0)
local cpu = make_graph("widgets.sys.cpu", "CPU", colors.red, 0)

-- Helper to parse sbar.exec output to string
local function to_str(output)
  if type(output) == "table" then
    return tostring(output[1] or output.stdout or "")
  end
  return tostring(output or "")
end

-- Query P/E core counts at startup (hardcoded sysctl commands)
local ncores = tonumber(io.popen("sysctl -n hw.ncpu"):read("*a"):match("(%d+)")) or 10
local p_cores = tonumber(io.popen("sysctl -n hw.perflevel0.logicalcpu 2>/dev/null"):read("*a"):match("(%d+)")) or ncores
local e_cores = tonumber(io.popen("sysctl -n hw.perflevel1.logicalcpu 2>/dev/null"):read("*a"):match("(%d+)")) or 0

--------------------------------------------------------------------------------
-- CPU POPUP
--------------------------------------------------------------------------------
local cpu_popup_width = 550
local cpu_popup = center_popup.create("cpu.popup", {
  width = cpu_popup_width,
  height = 600,
  popup_height = 26,
  title = "CPU",
  meta = "",
  auto_hide = false,
  accent_color = colors.red,
})
cpu_popup.meta_item:set({ drawing = false })
cpu_popup.body_item:set({ drawing = false })
cpu_popup.anchor:subscribe("mouse.exited.global", function(_)
  cpu_popup.hide()
end)

local cpu_popup_pos = cpu_popup.position
local cpu_name_width = 280
local cpu_value_width = cpu_popup_width - cpu_name_width

local function cpu_add_row(key, title)
  return sbar.add("item", "cpu.popup." .. key, {
    position = cpu_popup_pos,
    width = cpu_popup_width,
    icon = {
      align = "left",
      string = title,
      width = cpu_name_width,
      font = { family = settings.font.text, style = settings.font.style_map["Semibold"], size = 11.0 },
    },
    label = {
      align = "right",
      string = "-",
      width = cpu_value_width,
      font = { family = settings.font.numbers, style = settings.font.style_map["Regular"], size = 11.0 },
    },
    background = { drawing = false },
  })
end

-- OVERVIEW section
cpu_popup.add_section("overview", "OVERVIEW")
local cpu_row_total = cpu_add_row("total", "Total Usage")
local cpu_row_temp = cpu_add_row("temp", "Temperature")
local cpu_row_load = cpu_add_row("load", "Load Average")
local cpu_row_uptime = cpu_add_row("uptime", "Uptime")
local cpu_row_cores = cpu_add_row("cores", "Cores")

-- CORES section
cpu_popup.add_section("cores", "CORES")

local cpu_core_sliders = {}
for i = 0, ncores - 1 do
  local is_p = (i < p_cores)
  local label = is_p and string.format("P%d", i) or string.format("E%d", i - p_cores)
  local color = is_p and colors.red or colors.blue

  cpu_core_sliders[i] = sbar.add("slider", "cpu.popup.core_" .. i, cpu_popup_width - 100, {
    position = cpu_popup_pos,
    slider = {
      highlight_color = color,
      percentage = 0,
      background = { height = 5, corner_radius = 2, color = colors.surface0 },
      knob = { drawing = false },
    },
    icon = {
      string = label,
      width = 30,
      font = { family = settings.font.text, style = settings.font.style_map["Semibold"], size = 10.0 },
      color = color,
    },
    label = {
      string = "0%",
      width = 40,
      align = "right",
      font = { family = settings.font.numbers, style = settings.font.style_map["Regular"], size = 10.0 },
    },
    background = { drawing = false },
  })
end

-- TOP PROCESSES section
cpu_popup.add_section("procs", "TOP PROCESSES")
local cpu_proc_rows = {}
for i = 1, 5 do
  cpu_proc_rows[i] = cpu_add_row("proc" .. i, "")
end

cpu_popup.add_close_row({ label = "close x" })

-- Hardcoded system commands for popup refresh
local function refresh_cpu_popup()
  local core_str = ncores .. " cores"
  if p_cores and e_cores and e_cores > 0 then
    core_str = core_str .. " (" .. p_cores .. "P + " .. e_cores .. "E)"
  end
  cpu_row_cores:set({ label = { string = core_str } })

  sbar.exec("sysctl -n vm.loadavg 2>/dev/null", function(out)
    local text = to_str(out):gsub("[{}]", ""):gsub("^%s+", ""):gsub("%s+$", "")
    cpu_row_load:set({ label = { string = text ~= "" and text or "-" } })
  end)

  sbar.exec("uptime 2>/dev/null", function(out)
    local text = to_str(out)
    local up = text:match("up%s+(.-),%s+%d+ user") or text:match("up%s+(.-)$") or "-"
    up = up:gsub("^%s+", ""):gsub("%s+$", "")
    cpu_row_uptime:set({ label = { string = up } })
  end)

  sbar.exec("ps -Aceo pcpu,comm -r | head -6 | tail -5", function(output)
    local text = to_str(output):gsub("^%s+", ""):gsub("%s+$", "")
    local idx = 1
    for line in text:gmatch("[^\r\n]+") do
      if idx > 5 then break end
      local val, proc_name = line:match("^%s*([%d%.]+)%s+(.+)$")
      if val and proc_name then
        if #proc_name > 30 then proc_name = proc_name:sub(1, 27) .. "..." end
        cpu_proc_rows[idx]:set({
          icon = { string = proc_name },
          label = { string = val .. "%" },
        })
        idx = idx + 1
      end
    end
    for j = idx, 5 do
      cpu_proc_rows[j]:set({ icon = { string = "" }, label = { string = "" } })
    end
  end)
end

cpu_popup.title_item:subscribe("mouse.clicked", function(env)
  if env.BUTTON == "left" then refresh_cpu_popup() end
end)

--------------------------------------------------------------------------------
-- GPU POPUP
--------------------------------------------------------------------------------
local gpu_popup_width = 500
local gpu_popup = center_popup.create("gpu.popup", {
  width = gpu_popup_width,
  height = 500,
  popup_height = 26,
  title = "GPU",
  meta = "",
  auto_hide = false,
  accent_color = colors.mauve,
})
gpu_popup.meta_item:set({ drawing = false })
gpu_popup.body_item:set({ drawing = false })
gpu_popup.anchor:subscribe("mouse.exited.global", function(_)
  gpu_popup.hide()
end)

local gpu_popup_pos = gpu_popup.position
local gpu_name_width = 240
local gpu_value_width = gpu_popup_width - gpu_name_width

local function gpu_add_row(key, title)
  return sbar.add("item", "gpu.popup." .. key, {
    position = gpu_popup_pos,
    width = gpu_popup_width,
    icon = {
      align = "left",
      string = title,
      width = gpu_name_width,
      font = { family = settings.font.text, style = settings.font.style_map["Semibold"], size = 11.0 },
    },
    label = {
      align = "right",
      string = "-",
      width = gpu_value_width,
      font = { family = settings.font.numbers, style = settings.font.style_map["Regular"], size = 11.0 },
    },
    background = { drawing = false },
  })
end

-- OVERVIEW section
gpu_popup.add_section("overview", "OVERVIEW")
local gpu_row_util = gpu_add_row("util", "Usage")
local gpu_row_temp = gpu_add_row("temp", "Temperature")

-- TOP PROCESSES section
gpu_popup.add_section("procs", "TOP PROCESSES")
local gpu_proc_rows = {}
for i = 1, 10 do
  gpu_proc_rows[i] = gpu_add_row("proc" .. i, "")
end

gpu_popup.add_close_row({ label = "close x" })

local function format_gpu_time(ns)
  ns = tonumber(ns) or 0
  if ns >= 1000000000 then
    return string.format("%.1fs", ns / 1000000000)
  elseif ns >= 1000000 then
    return string.format("%.0fms", ns / 1000000)
  else
    return string.format("%.0fus", ns / 1000)
  end
end

-- Cached gpu procs string from last event
local _cached_gpu_procs = ""

local function refresh_gpu_popup()
  local idx = 1
  if _cached_gpu_procs ~= "" then
    for entry in _cached_gpu_procs:gmatch("[^;]+") do
      if idx > 10 then break end
      local name, time_str = entry:match("^(.+):(%d+)$")
      if name and time_str then
        if #name > 30 then name = name:sub(1, 27) .. "..." end
        gpu_proc_rows[idx]:set({
          icon = { string = name },
          label = { string = format_gpu_time(time_str) },
        })
        idx = idx + 1
      end
    end
  end
  for j = idx, 10 do
    gpu_proc_rows[j]:set({ icon = { string = "" }, label = { string = "" } })
  end
end

gpu_popup.title_item:subscribe("mouse.clicked", function(env)
  if env.BUTTON == "left" then refresh_gpu_popup() end
end)

--------------------------------------------------------------------------------
-- MEM POPUP
--------------------------------------------------------------------------------
local mem_popup_width = 500
local mem_popup = center_popup.create("mem.popup", {
  width = mem_popup_width,
  height = 500,
  popup_height = 26,
  title = "MEMORY",
  meta = "",
  auto_hide = false,
  accent_color = colors.teal,
})
mem_popup.meta_item:set({ drawing = false })
mem_popup.body_item:set({ drawing = false })
mem_popup.anchor:subscribe("mouse.exited.global", function(_)
  mem_popup.hide()
end)

local mem_popup_pos = mem_popup.position
local mem_name_width = 240
local mem_value_width = mem_popup_width - mem_name_width

local function mem_add_row(key, title)
  return sbar.add("item", "mem.popup." .. key, {
    position = mem_popup_pos,
    width = mem_popup_width,
    icon = {
      align = "left",
      string = title,
      width = mem_name_width,
      font = { family = settings.font.text, style = settings.font.style_map["Semibold"], size = 11.0 },
    },
    label = {
      align = "right",
      string = "-",
      width = mem_value_width,
      font = { family = settings.font.numbers, style = settings.font.style_map["Regular"], size = 11.0 },
    },
    background = { drawing = false },
  })
end

-- OVERVIEW section
mem_popup.add_section("overview", "OVERVIEW")
local mem_row_used = mem_add_row("used", "Used / Total")
local mem_row_pressure = mem_add_row("pressure", "Memory Pressure")
local mem_row_swap = mem_add_row("swap", "Swap")

-- TOP PROCESSES section
mem_popup.add_section("procs", "TOP PROCESSES")
local mem_proc_rows = {}
for i = 1, 5 do
  mem_proc_rows[i] = mem_add_row("proc" .. i, "")
end

mem_popup.add_close_row({ label = "close x" })

-- Hardcoded system commands for popup refresh
local function refresh_mem_popup()
  sbar.exec("sysctl -n kern.memorystatus_level 2>/dev/null", function(out)
    local pressure = to_str(out):match("(%d+)")
    mem_row_pressure:set({ label = { string = pressure and (pressure .. "%") or "-" } })
  end)

  sbar.exec("sysctl -n vm.swapusage 2>/dev/null", function(out)
    local text = to_str(out):gsub("%s+$", "")
    local used = text:match("used = ([%d%.]+%w+)")
    local total = text:match("total = ([%d%.]+%w+)")
    if used and total then
      mem_row_swap:set({ label = { string = used .. " / " .. total } })
    else
      mem_row_swap:set({ label = { string = "-" } })
    end
  end)

  sbar.exec("ps -Aceo rss,comm -m | head -6 | tail -5", function(output)
    local text = to_str(output):gsub("^%s+", ""):gsub("%s+$", "")
    local idx = 1
    for line in text:gmatch("[^\r\n]+") do
      if idx > 5 then break end
      local val, proc_name = line:match("^%s*([%d%.]+)%s+(.+)$")
      if val and proc_name then
        if #proc_name > 30 then proc_name = proc_name:sub(1, 27) .. "..." end
        local kb = tonumber(val) or 0
        local display_val
        if kb >= 1048576 then
          display_val = string.format("%.1f GB", kb / 1048576)
        elseif kb >= 1024 then
          display_val = string.format("%.0f MB", kb / 1024)
        else
          display_val = string.format("%d KB", kb)
        end
        mem_proc_rows[idx]:set({
          icon = { string = proc_name },
          label = { string = display_val },
        })
        idx = idx + 1
      end
    end
    for j = idx, 5 do
      mem_proc_rows[j]:set({ icon = { string = "" }, label = { string = "" } })
    end
  end)
end

mem_popup.title_item:subscribe("mouse.clicked", function(env)
  if env.BUTTON == "left" then refresh_mem_popup() end
end)

--------------------------------------------------------------------------------
-- CLICK HANDLERS
--------------------------------------------------------------------------------
cpu:subscribe("mouse.clicked", function(env)
  if env.BUTTON == "left" then
    if cpu_popup.is_showing() then
      cpu_popup.hide()
    else
      cpu_popup.show(function() refresh_cpu_popup() end)
    end
  end
end)

gpu:subscribe("mouse.clicked", function(env)
  if env.BUTTON == "left" then
    if gpu_popup.is_showing() then
      gpu_popup.hide()
    else
      gpu_popup.show(function() refresh_gpu_popup() end)
    end
  end
end)

mem:subscribe("mouse.clicked", function(env)
  if env.BUTTON == "left" then
    if mem_popup.is_showing() then
      mem_popup.hide()
    else
      mem_popup.show(function() refresh_mem_popup() end)
    end
  end
end)

--------------------------------------------------------------------------------
-- EVENT: system_stats_update
--------------------------------------------------------------------------------
cpu:subscribe("system_stats_update", function(env)
  if _G.SKETCHYBAR_SUSPENDED then return end

  local cpu_total = tonumber(env.cpu_total)
  local cpu_temp_val = tonumber(env.cpu_temp)

  -- CPU bar label: "14% 38°"
  if cpu_total then
    cpu:push({ cpu_total / 100.0 })
    local lbl = string.format("%d%%", cpu_total)
    if cpu_temp_val and cpu_temp_val >= 0 then
      lbl = lbl .. string.format(" %d°", cpu_temp_val)
    end
    cpu:set({ label = lbl })
  else
    cpu:set({ label = "--" })
  end

  -- GPU bar label: "0% 39°"
  local gpu_util = tonumber(env.gpu_util)
  local gpu_temp_val = tonumber(env.gpu_temp)
  if gpu_util and gpu_util >= 0 then
    gpu:push({ gpu_util / 100.0 })
    local lbl = string.format("%d%%", gpu_util)
    if gpu_temp_val and gpu_temp_val >= 0 then
      lbl = lbl .. string.format(" %d°", gpu_temp_val)
    end
    gpu:set({ label = lbl })
  else
    gpu:set({ label = "--" })
  end

  -- MEM bar label: "62% 8/16G"
  local mem_percent = tonumber(env.mem_used_percent)
  local mem_used_gb = tonumber(env.mem_used_gb)
  local mem_total_gb = tonumber(env.mem_total_gb)
  if mem_percent and mem_percent >= 0 then
    mem:push({ mem_percent / 100.0 })
    local lbl = string.format("%d%%", mem_percent)
    if mem_used_gb and mem_total_gb then
      lbl = lbl .. string.format(" %.0f/%.0fG", mem_used_gb, mem_total_gb)
    end
    mem:set({ label = lbl })
  else
    mem:set({ label = "--" })
  end

  -- Cache gpu procs for popup
  _cached_gpu_procs = env.gpu_procs or ""

  -- Update CPU popup if visible
  if cpu_popup.is_showing() then
    cpu_row_total:set({ label = { string = cpu_total and string.format("%d%%", cpu_total) or "-" } })
    cpu_row_temp:set({ label = { string = (cpu_temp_val and cpu_temp_val >= 0) and string.format("%d°C", cpu_temp_val) or "-" } })

    -- Update per-core sliders
    local core_loads_str = env.cpu_core_loads or ""
    local core_idx = 0
    for load_str in core_loads_str:gmatch("([^,]+)") do
      if cpu_core_sliders[core_idx] then
        local load = tonumber(load_str) or 0
        cpu_core_sliders[core_idx]:set({
          slider = { percentage = load },
          label = { string = load .. "%" },
        })
      end
      core_idx = core_idx + 1
    end
  end

  -- Update GPU popup if visible
  if gpu_popup.is_showing() then
    gpu_row_util:set({ label = { string = gpu_util and string.format("%d%%", gpu_util) or "-" } })
    gpu_row_temp:set({ label = { string = (gpu_temp_val and gpu_temp_val >= 0) and string.format("%d°C", gpu_temp_val) or "-" } })
    refresh_gpu_popup()
  end

  -- Update MEM popup if visible
  if mem_popup.is_showing() then
    if mem_percent then
      local ml = string.format("%d%%", mem_percent)
      if mem_used_gb and mem_total_gb then
        ml = string.format("%.1f / %.0f GB (%d%%)", mem_used_gb, mem_total_gb, mem_percent)
      end
      mem_row_used:set({ label = { string = ml } })
    end
  end
end)

--------------------------------------------------------------------------------
-- Keep network cache for wifi.lua
--------------------------------------------------------------------------------
_G._system_stats_net = _G._system_stats_net or { down = 0, up = 0 }

cpu:subscribe("network_update", function(env)
  local down = tonumber(env.download) or 0
  local up = tonumber(env.upload) or 0
  _G._system_stats_net.down = down
  _G._system_stats_net.up = up
end)
