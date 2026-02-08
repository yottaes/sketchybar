local colors = require("colors")
local settings = require("settings")
local center_popup = require("center_popup")

-- Launch native system_stats helper (CPU/GPU/temp/memory event provider)
-- NOTE: sbar.exec is the SketchyBar Lua API (not Node.js); all commands are hardcoded
sbar.exec("killall system_stats >/dev/null 2>&1; " .. os.getenv("CONFIG_DIR") .. "/helpers/system_stats/bin/system_stats system_stats_update 2.0")

local graph_width = 80

-- Simple graph widget: icon = name label, label = combined stats on one line
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
local row_cpu_cores = add_row("cpu_cores", "Cores")
local row_cpu_load = add_row("cpu_load", "Load Average")
local row_cpu_uptime = add_row("cpu_uptime", "Uptime")
local cpu_proc_rows = {}
for i = 1, 5 do
  cpu_proc_rows[i] = add_row("cpu_proc" .. i, "")
end

-- MEM section
stats_popup.add_section("mem", "MEMORY")
local row_mem_used = add_row("mem_used", "Used / Total")
local row_mem_pressure = add_row("mem_pressure", "Memory Pressure")
local row_mem_swap = add_row("mem_swap", "Swap")
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

-- Helper to parse sbar.exec output to string
local function to_str(output)
  if type(output) == "table" then
    return tostring(output[1] or output.stdout or "")
  end
  return tostring(output or "")
end

-- Fetch and display detailed system info (all hardcoded commands, no user input)
local function refresh_popup()
  -- CPU cores + model
  sbar.exec("sysctl -n machdep.cpu.brand_string 2>/dev/null", function(out)
    local brand = to_str(out):gsub("%s+$", "")
    sbar.exec("sysctl -n hw.ncpu 2>/dev/null", function(ncpu_out)
      local ncpu = to_str(ncpu_out):match("(%d+)") or "?"
      sbar.exec("sysctl -n hw.perflevel0.logicalcpu 2>/dev/null", function(perf_out)
        local p_cores = to_str(perf_out):match("(%d+)")
        sbar.exec("sysctl -n hw.perflevel1.logicalcpu 2>/dev/null", function(eff_out)
          local e_cores = to_str(eff_out):match("(%d+)")
          local core_str = ncpu .. " cores"
          if p_cores and e_cores then
            core_str = core_str .. " (" .. p_cores .. "P + " .. e_cores .. "E)"
          end
          row_cpu_cores:set({ label = { string = core_str } })
        end)
      end)
    end)
  end)

  -- Load average
  sbar.exec("sysctl -n vm.loadavg 2>/dev/null", function(out)
    local text = to_str(out):gsub("[{}]", ""):gsub("^%s+", ""):gsub("%s+$", "")
    row_cpu_load:set({ label = { string = text ~= "" and text or "-" } })
  end)

  -- Uptime
  sbar.exec("uptime 2>/dev/null", function(out)
    local text = to_str(out)
    local up = text:match("up%s+(.-),%s+%d+ user") or text:match("up%s+(.-)$") or "-"
    up = up:gsub("^%s+", ""):gsub("%s+$", "")
    row_cpu_uptime:set({ label = { string = up } })
  end)

  -- CPU top 5 processes (hardcoded ps command)
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
    for i = idx, 5 do
      cpu_proc_rows[i]:set({ icon = { string = "" }, label = { string = "" } })
    end
  end)

  -- Memory: used/free/total from vm_stat + sysctl
  sbar.exec("sysctl -n hw.memsize 2>/dev/null", function(memsize_out)
    local total_bytes = tonumber(to_str(memsize_out):match("(%d+)")) or 0
    local total_gb = total_bytes / (1024 * 1024 * 1024)
    sbar.exec("vm_stat 2>/dev/null", function(vm_out)
      local text = to_str(vm_out)
      local page_size = tonumber(text:match("page size of (%d+)")) or 16384
      local active = tonumber(text:match("Pages active:%s+(%d+)")) or 0
      local wired = tonumber(text:match("Pages wired down:%s+(%d+)")) or 0
      local compressed = tonumber(text:match("Pages occupied by compressor:%s+(%d+)")) or 0
      local speculative = tonumber(text:match("Pages speculative:%s+(%d+)")) or 0
      local used_bytes = (active + wired + compressed + speculative) * page_size
      local used_gb = used_bytes / (1024 * 1024 * 1024)
      if total_gb > 0 then
        local pct = math.floor(used_gb / total_gb * 100 + 0.5)
        row_mem_used:set({ label = { string = string.format("%.1f / %.0f GB (%d%%)", used_gb, total_gb, pct) } })
      end
    end)
  end)

  -- Memory pressure
  sbar.exec("sysctl -n kern.memorystatus_level 2>/dev/null", function(out)
    local pressure = to_str(out):match("(%d+)")
    row_mem_pressure:set({ label = { string = pressure and (pressure .. "%") or "-" } })
  end)

  -- Swap usage
  sbar.exec("sysctl -n vm.swapusage 2>/dev/null", function(out)
    local text = to_str(out):gsub("%s+$", "")
    local used = text:match("used = ([%d%.]+%w+)")
    local total = text:match("total = ([%d%.]+%w+)")
    if used and total then
      row_mem_swap:set({ label = { string = used .. " / " .. total } })
    else
      row_mem_swap:set({ label = { string = "-" } })
    end
  end)

  -- MEM top 5 processes (hardcoded ps command)
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
    for i = idx, 5 do
      mem_proc_rows[i]:set({ icon = { string = "" }, label = { string = "" } })
    end
  end)

  -- Network interface + IP (hardcoded commands)
  local wifi_iface = os.getenv("WIFI_INTERFACE") or "en0"
  sbar.exec("/usr/sbin/ipconfig getifaddr " .. wifi_iface .. " 2>/dev/null", function(ip_out)
    local ip = to_str(ip_out):gsub("%s+$", "")
    row_net_ip:set({ label = { string = ip ~= "" and ip or "-" } })
    row_net_iface:set({ label = { string = wifi_iface } })
  end)

  -- Network speeds from cached global
  local net = _G._system_stats_net or { down = 0, up = 0 }
  local function fmt_net(mbps)
    if mbps >= 1000 then return string.format("%.1f Gbps", mbps / 1000) end
    if mbps >= 1 then return string.format("%.0f Mbps", mbps) end
    return string.format("%.0f Kbps", mbps * 1000)
  end
  row_net_down:set({ label = { string = fmt_net(net.down) } })
  row_net_up:set({ label = { string = fmt_net(net.up) } })
end

stats_popup.title_item:subscribe("mouse.clicked", function(env)
  if env.BUTTON == "left" then refresh_popup() end
end)

local function toggle_popup()
  if stats_popup.is_showing() then
    stats_popup.hide()
  else
    stats_popup.show(function() refresh_popup() end)
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

  -- CPU: "14% 38°C"
  local cpu_total = tonumber(env.cpu_total)
  local cpu_temp_val = tonumber(env.cpu_temp)
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

  -- GPU: "0% 39°C"
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

  -- MEM: "62% 8.2/16G"
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

  -- Update popup rows if visible
  if stats_popup.is_showing() then
    row_cpu_total:set({ label = { string = cpu_total and string.format("%d%%", cpu_total) or "-" } })
    row_cpu_temp:set({ label = { string = (cpu_temp_val and cpu_temp_val >= 0) and string.format("%d°C", cpu_temp_val) or "-" } })
    row_gpu_util:set({ label = { string = gpu_util and string.format("%d%%", gpu_util) or "-" } })
    row_gpu_temp:set({ label = { string = (gpu_temp_val and gpu_temp_val >= 0) and string.format("%d°C", gpu_temp_val) or "-" } })
    if mem_percent then
      local ml = string.format("%d%%", mem_percent)
      if mem_used_gb and mem_total_gb then
        ml = string.format("%.1f / %.0f GB (%d%%)", mem_used_gb, mem_total_gb, mem_percent)
      end
      row_mem_used:set({ label = { string = ml } })
    end
  end
end)

_G._system_stats_net = _G._system_stats_net or { down = 0, up = 0 }

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
