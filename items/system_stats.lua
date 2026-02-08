local colors = require("colors")
local settings = require("settings")
local center_popup = require("center_popup")

-- Launch native system_stats helper (CPU/GPU/temp/memory event provider)
-- NOTE: sbar.exec is the SketchyBar Lua API (not Node.js); all commands are hardcoded
sbar.exec("killall system_stats >/dev/null 2>&1; " .. os.getenv("CONFIG_DIR") .. "/helpers/system_stats/bin/system_stats system_stats_update 2.0")

-- Widget dimensions: each widget is ~100px graph with icon (name) and label (stat)
local graph_width = 100

-- Helper: create a 3-column widget (name | stats | graph)
-- The graph item provides the graph background.
-- icon = stat name (left-aligned), label = primary stat (top, y_offset=+4)
-- An overlay item shows the secondary stat (bottom, y_offset=-4)
local function make_stat_widget(name, label_text, graph_color, padding_right)
  local graph = sbar.add("graph", name, graph_width, {
    position = "right",
    graph = { color = colors.with_alpha(graph_color, 0.4) },
    icon = {
      string = label_text,
      color = graph_color,
      font = {
        family = settings.font.text,
        style = settings.font.style_map["Heavy"],
        size = 9.0,
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
      padding_left = 0,
      padding_right = 6,
      width = 0,
      y_offset = 4,
    },
    padding_left = 0,
    padding_right = padding_right or 0,
  })

  -- Overlay item for the second stat line (y_offset=-4)
  -- width=0 ensures this item takes no layout space (it overlaps the graph)
  local overlay = sbar.add("item", name .. ".sub", {
    position = "right",
    width = 0,
    icon = { drawing = false },
    label = {
      string = "--",
      color = colors.subtext0,
      font = {
        family = settings.font.numbers,
        style = settings.font.style_map["Regular"],
        size = 8.0,
      },
      align = "right",
      padding_left = 0,
      padding_right = 6,
      y_offset = -4,
    },
    padding_left = 0,
    padding_right = 0,
    background = { drawing = false },
  })

  return graph, overlay
end

local trailing_gap = 16
local mem, mem_sub = make_stat_widget("widgets.sys.mem", "MEM", colors.teal, trailing_gap)
local gpu, gpu_sub = make_stat_widget("widgets.sys.gpu", "GPU", colors.mauve, 0)
local cpu, cpu_sub = make_stat_widget("widgets.sys.cpu", "CPU", colors.red, 0)

-- Unified popup for all system stats
local popup_width = 500
local stats_popup = center_popup.create("system_stats.popup", {
  width = popup_width,
  height = 600,
  popup_height = 26,
  title = "System Stats",
  meta = "",
  auto_hide = false,
})
stats_popup.meta_item:set({ drawing = false })
stats_popup.body_item:set({ drawing = false })

local popup_pos = stats_popup.position
local name_width = 240
local value_width = popup_width - name_width

local function add_row(key, title)
  return sbar.add("item", "system_stats.popup." .. key, {
    position = popup_pos,
    width = popup_width,
    icon = {
      align = "left",
      string = title,
      width = name_width,
      font = { family = settings.font.text, style = settings.font.style_map["Regular"], size = 11.0 },
    },
    label = {
      align = "right",
      string = "-",
      width = value_width,
      font = { family = settings.font.numbers, style = settings.font.style_map["Regular"], size = 11.0 },
    },
    background = { drawing = false },
  })
end

-- CPU section
stats_popup.add_section("cpu", "CPU")
local row_cpu_total = add_row("cpu_total", "Total Usage")
local row_cpu_temp = add_row("cpu_temp", "Temperature")
local cpu_proc_rows = {}
for i = 1, 5 do
  cpu_proc_rows[i] = add_row("cpu_proc" .. i, "")
end

-- MEM section
stats_popup.add_section("mem", "MEMORY")
local row_mem_used = add_row("mem_used", "Used / Total")
local row_mem_pressure = add_row("mem_pressure", "Memory Pressure")
local mem_proc_rows = {}
for i = 1, 5 do
  mem_proc_rows[i] = add_row("mem_proc" .. i, "")
end

-- GPU section
stats_popup.add_section("gpu", "GPU")
local row_gpu_util = add_row("gpu_util", "Usage")
local row_gpu_temp = add_row("gpu_temp", "Temperature")

-- NET section
stats_popup.add_section("net", "NETWORK")
local row_net_down = add_row("net_down", "Download")
local row_net_up = add_row("net_up", "Upload")
local row_net_iface = add_row("net_iface", "Interface")
local row_net_ip = add_row("net_ip", "IP Address")

stats_popup.add_close_row({ label = "close x" })

-- Fetch and display top processes for popup (hardcoded commands, no user input)
local function refresh_popup()
  -- CPU top 5 (hardcoded ps command)
  sbar.exec("ps -Aceo pcpu,comm -r | head -6 | tail -5", function(output)
    local text = tostring(type(output) == "table" and (output[1] or output.stdout or "") or output or "")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
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
    for i = idx, 5 do
      cpu_proc_rows[i]:set({ icon = { string = "" }, label = { string = "" } })
    end
  end)

  -- MEM top 5 (hardcoded ps command)
  sbar.exec("ps -Aceo rss,comm -m | head -6 | tail -5", function(output)
    local text = tostring(type(output) == "table" and (output[1] or output.stdout or "") or output or "")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
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
    for i = idx, 5 do
      mem_proc_rows[i]:set({ icon = { string = "" }, label = { string = "" } })
    end
  end)

  -- Memory pressure (hardcoded sysctl command)
  sbar.exec("sysctl -n kern.memorystatus_level 2>/dev/null", function(out)
    local pressure = tostring(out or ""):match("(%d+)")
    row_mem_pressure:set({ label = { string = pressure and (pressure .. "%") or "-" } })
  end)

  -- Network interface + IP (hardcoded commands)
  local wifi_iface = os.getenv("WIFI_INTERFACE") or "en0"
  sbar.exec("/usr/sbin/ipconfig getifaddr " .. wifi_iface .. " 2>/dev/null", function(ip_out)
    local ip = tostring(ip_out or ""):gsub("%s+$", "")
    row_net_ip:set({ label = { string = ip ~= "" and ip or "-" } })
    row_net_iface:set({ label = { string = wifi_iface } })
  end)
end

stats_popup.title_item:subscribe("mouse.clicked", function(env)
  if env.BUTTON == "left" then
    refresh_popup()
  end
end)

local function toggle_popup()
  if stats_popup.is_showing() then
    stats_popup.hide()
  else
    stats_popup.show(function()
      refresh_popup()
    end)
  end
end

cpu:subscribe("mouse.clicked", function(env)
  if env.BUTTON == "left" then toggle_popup() end
end)

gpu:subscribe("mouse.clicked", function(env)
  if env.BUTTON == "left" then toggle_popup() end
end)

mem:subscribe("mouse.clicked", function(env)
  if env.BUTTON == "left" then toggle_popup() end
end)

cpu:subscribe("system_stats_update", function(env)
  if _G.SKETCHYBAR_SUSPENDED then return end

  -- CPU
  local cpu_total = tonumber(env.cpu_total)
  local cpu_temp_val = tonumber(env.cpu_temp)

  if cpu_total then
    cpu:push({ cpu_total / 100.0 })
    cpu:set({ label = string.format("%d%%", cpu_total) })
  else
    cpu:set({ label = "--" })
  end

  if cpu_temp_val and cpu_temp_val >= 0 then
    cpu_sub:set({ label = string.format("%d°C", cpu_temp_val) })
  else
    cpu_sub:set({ label = "--" })
  end

  -- GPU
  local gpu_util = tonumber(env.gpu_util)
  local gpu_temp_val = tonumber(env.gpu_temp)

  if gpu_util and gpu_util >= 0 then
    gpu:push({ gpu_util / 100.0 })
    gpu:set({ label = string.format("%d%%", gpu_util) })
  else
    gpu:set({ label = "--" })
  end

  if gpu_temp_val and gpu_temp_val >= 0 then
    gpu_sub:set({ label = string.format("%d°C", gpu_temp_val) })
  else
    gpu_sub:set({ label = "--" })
  end

  -- MEM
  local mem_percent = tonumber(env.mem_used_percent)
  local mem_used_gb = tonumber(env.mem_used_gb)
  local mem_total_gb = tonumber(env.mem_total_gb)

  if mem_percent and mem_percent >= 0 then
    mem:push({ mem_percent / 100.0 })
    mem:set({ label = string.format("%d%%", mem_percent) })
  else
    mem:set({ label = "--" })
  end

  if mem_used_gb and mem_total_gb then
    mem_sub:set({ label = string.format("%.1f/%.0fG", mem_used_gb, mem_total_gb) })
  else
    mem_sub:set({ label = "--" })
  end

  -- Update popup rows if visible
  if stats_popup.is_showing() then
    row_cpu_total:set({ label = { string = cpu_total and string.format("%d%%", cpu_total) or "-" } })
    row_cpu_temp:set({ label = { string = (cpu_temp_val and cpu_temp_val >= 0) and string.format("%d°C", cpu_temp_val) or "-" } })
    row_gpu_util:set({ label = { string = gpu_util and string.format("%d%%", gpu_util) or "-" } })
    row_gpu_temp:set({ label = { string = (gpu_temp_val and gpu_temp_val >= 0) and string.format("%d°C", gpu_temp_val) or "-" } })
    if mem_percent then
      local mem_label = string.format("%d%%", mem_percent)
      if mem_used_gb and mem_total_gb then
        mem_label = string.format("%.1f / %.0f GB (%d%%)", mem_used_gb, mem_total_gb, mem_percent)
      end
      row_mem_used:set({ label = { string = mem_label } })
    end
  end
end)

-- Network rate tracking for popup (updated by wifi.lua's network_update event)
-- Store latest rates so popup can display them
_G._system_stats_net = _G._system_stats_net or { down = 0, up = 0 }

-- Subscribe to network_update to keep popup NET rows current
cpu:subscribe("network_update", function(env)
  local down = tonumber(env.download) or 0
  local up = tonumber(env.upload) or 0
  _G._system_stats_net.down = down
  _G._system_stats_net.up = up

  if stats_popup.is_showing() then
    local function fmt(mbps)
      if mbps >= 1000 then return string.format("%.1f Gbps", mbps / 1000) end
      if mbps >= 1 then return string.format("%.0f Mbps", mbps) end
      return string.format("%.0f Kbps", mbps * 1000)
    end
    row_net_down:set({ label = { string = fmt(down) } })
    row_net_up:set({ label = { string = fmt(up) } })
  end
end)
