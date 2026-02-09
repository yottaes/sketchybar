local colors = require("colors")
local settings = require("settings")

-- CPU per-core bars + GPU/MEM graphs. No popups.
-- NOTE: sbar.exec is the SketchyBar Lua API, NOT Node.js child_process.
-- All commands below are hardcoded strings with no user input.
sbar.exec(
	"killall system_stats >/dev/null 2>&1; "
		.. os.getenv("CONFIG_DIR")
		.. "/helpers/system_stats/bin/system_stats system_stats_update 0.5"
)

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

-- Right-click opens Activity Monitor (hardcoded app path)
gpu:subscribe("mouse.clicked", function(env)
	if env.BUTTON == "right" then
		sbar.exec("/usr/bin/open -a 'Activity Monitor' >/dev/null 2>&1", function() end)
	end
end)

mem:subscribe("mouse.clicked", function(env)
	if env.BUTTON == "right" then
		sbar.exec("/usr/bin/open -a 'Activity Monitor' >/dev/null 2>&1", function() end)
	end
end)

--------------------------------------------------------------------------------
-- CPU PER-CORE VERTICAL BARS
--------------------------------------------------------------------------------
local ncores = tonumber(io.popen("sysctl -n hw.ncpu"):read("*a"):match("(%d+)")) or 10

local max_bar_height = 28
local bar_width = 6

local function color_for_load(load)
	if load >= 75 then
		return colors.red
	end
	if load >= 50 then
		return colors.peach
	end
	if load >= 25 then
		return colors.yellow
	end
	return colors.green
end

-- Create core items right-to-left (rightmost core first)
local core_items = {}
for i = ncores - 1, 0, -1 do
	local pr = 1
	if i == ncores - 1 then
		pr = trailing_gap
	end -- gap between cores and GPU
	core_items[i] = sbar.add("item", "widgets.sys.cpu.core_" .. i, {
		position = "right",
		width = bar_width,
		icon = { drawing = false },
		label = { drawing = false },
		background = {
			color = colors.green,
			height = 3,
			corner_radius = 2,
			y_offset = -(max_bar_height - 3) / 2,
		},
		padding_left = 0,
		padding_right = pr,
	})
end

-- CPU info: icon = temp (top), label = load (bottom), overlapping at same x
local cpu_info = sbar.add("item", "widgets.sys.cpu.info", {
	position = "right",
	icon = {
		string = "",
		color = colors.text,
		font = {
			family = settings.font.numbers,
			style = settings.font.style_map["Bold"],
			size = 9.0,
		},
		width = 0,
		y_offset = 6,
	},
	label = {
		string = "--",
		color = colors.text,
		font = {
			family = settings.font.numbers,
			style = settings.font.style_map["Bold"],
			size = 9.0,
		},
		y_offset = -6,
		width = 20,
	},
	padding_left = 2,
	padding_right = 3,
})

-- CPU label (leftmost, just "CPU" text)
local cpu_label = sbar.add("item", "widgets.sys.cpu.label", {
	position = "right",
	icon = {
		string = "CPU",
		color = colors.red,
		font = {
			family = settings.font.text,
			style = settings.font.style_map["Heavy"],
			size = 12.0,
		},
		padding_left = 4,
		padding_right = 2,
	},
	label = { drawing = false },
	padding_left = 0,
	padding_right = 0,
})

cpu_label:subscribe("mouse.clicked", function(env)
	if env.BUTTON == "right" then
		sbar.exec("/usr/bin/open -a 'Activity Monitor' >/dev/null 2>&1", function() end)
	end
end)

local function update_core(idx, load)
	if not core_items[idx] then
		return
	end
	local h = math.max(3, math.floor(load / 100 * max_bar_height + 0.5))
	core_items[idx]:set({
		background = {
			color = color_for_load(load),
			height = h,
			y_offset = -(max_bar_height - h) / 2,
		},
	})
end

--------------------------------------------------------------------------------
-- EVENT: system_stats_update
--------------------------------------------------------------------------------
cpu_info:subscribe("system_stats_update", function(env)
	if _G.SKETCHYBAR_SUSPENDED then
		return
	end

	-- CPU stacked: temp on top, load on bottom
	local cpu_total = tonumber(env.cpu_total)
	local cpu_temp_val = tonumber(env.cpu_temp)
	cpu_info:set({
		icon = { string = (cpu_temp_val and cpu_temp_val >= 0) and string.format("%d\xc2\xb0", cpu_temp_val) or "" },
		label = { string = cpu_total and string.format("%d%%", cpu_total) or "--" },
	})

	-- Per-core bars
	local core_loads_str = env.cpu_core_loads or ""
	local core_idx = 0
	for load_str in core_loads_str:gmatch("([^,]+)") do
		update_core(core_idx, tonumber(load_str) or 0)
		core_idx = core_idx + 1
	end

	-- GPU graph
	local gpu_util = tonumber(env.gpu_util)
	local gpu_temp_val = tonumber(env.gpu_temp)
	if gpu_util and gpu_util >= 0 then
		gpu:push({ gpu_util / 100.0 })
		local lbl = string.format("%d%%", gpu_util)
		if gpu_temp_val and gpu_temp_val >= 0 then
			lbl = lbl .. string.format(" %d\xc2\xb0", gpu_temp_val)
		end
		gpu:set({ label = lbl })
	else
		gpu:set({ label = "--" })
	end

	-- MEM graph
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
end)

--------------------------------------------------------------------------------
-- Keep network cache for wifi.lua
--------------------------------------------------------------------------------
_G._system_stats_net = _G._system_stats_net or { down = 0, up = 0 }

cpu_info:subscribe("network_update", function(env)
	local down = tonumber(env.download) or 0
	local up = tonumber(env.upload) or 0
	_G._system_stats_net.down = down
	_G._system_stats_net.up = up
end)
