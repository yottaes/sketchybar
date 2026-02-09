local colors = require("colors")
local settings = require("settings")
local app_icons = require("app_icons")

-- Aerospace workspaces: show all workspaces that contain windows,
-- each with a workspace-ID pill and app icons for its windows.
-- Focused workspace is highlighted in lavender; others in surface0.
-- All sbar.exec() calls use hardcoded strings with no user input.

sbar.add("event", "aerospace_workspace_change")

local MAX_WORKSPACES = 10
local MAX_WINDOWS_PER_WS = 5

-- Track which workspace name is assigned to each slot (for click handling)
local slot_ws_name = {}

-- Pre-create workspace groups (pill + window icon slots)
local ws_groups = {}
for w = 1, MAX_WORKSPACES do
	local pill = sbar.add("item", "aerospace.ws." .. w .. ".pill", {
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
		padding_left = w == 1 and 2 or 6,
		padding_right = 2,
		background = {
			height = 22,
			corner_radius = 6,
			color = colors.lavender,
		},
		drawing = false,
	})

	local icons = {}
	for i = 1, MAX_WINDOWS_PER_WS do
		icons[i] = sbar.add("item", "aerospace.ws." .. w .. ".win." .. i, {
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

	-- Click a workspace pill to switch to it
	local slot = w
	pill:subscribe("mouse.clicked", function(_)
		local name = slot_ws_name[slot]
		if name then
			sbar.exec("aerospace workspace " .. name)
		end
	end)

	ws_groups[w] = { pill = pill, icons = icons }
end

-- Parse `aerospace list-windows --all` output into workspace -> app list map
local function parse_all_windows(output)
	local workspaces = {} -- ws_name -> { app1, app2, ... }
	local ws_seen = {}
	local ws_order = {}

	for line in output:gmatch("[^\r\n]+") do
		local ws, app = line:match("^(.-)|||(.-)$")
		if ws and app then
			ws = ws:match("^%s*(.-)%s*$")
			app = app:match("^%s*(.-)%s*$")
			if ws ~= "" and app ~= "" then
				if not ws_seen[ws] then
					ws_seen[ws] = true
					ws_order[#ws_order + 1] = ws
					workspaces[ws] = {}
				end
				workspaces[ws][#workspaces[ws] + 1] = app
			end
		end
	end

	table.sort(ws_order)
	return workspaces, ws_order
end

-- Ensure the focused workspace appears in the list (even if empty)
local function ensure_focused(workspaces, ws_order, focused_ws)
	if focused_ws == "" or workspaces[focused_ws] then
		return
	end
	workspaces[focused_ws] = {}
	local inserted = false
	for idx, name in ipairs(ws_order) do
		if focused_ws < name then
			table.insert(ws_order, idx, focused_ws)
			inserted = true
			break
		end
	end
	if not inserted then
		ws_order[#ws_order + 1] = focused_ws
	end
end

-- Apply workspace data to pre-created sketchybar items
local function render(workspaces, ws_order, focused_ws, focused_app)
	for w = 1, MAX_WORKSPACES do
		local ws_name = ws_order[w]
		slot_ws_name[w] = ws_name

		if ws_name then
			local is_focused_ws = (ws_name == focused_ws)
			ws_groups[w].pill:set({
				drawing = true,
				icon = {
					string = ws_name,
					color = is_focused_ws and colors.base or colors.text,
				},
				background = {
					color = is_focused_ws and colors.lavender or colors.surface0,
				},
			})

			local apps = workspaces[ws_name] or {}
			for i = 1, MAX_WINDOWS_PER_WS do
				local app = apps[i]
				if app then
					local icon_str = app_icons[app] or app_icons["Default"] or ":default:"
					local is_app_font = icon_str:match("^:.*:$")
					local is_focused = (is_focused_ws and app == focused_app)
					ws_groups[w].icons[i]:set({
						drawing = true,
						icon = {
							string = icon_str,
							font = {
								family = is_app_font and "sketchybar-app-font" or settings.font.icons,
								style = "Regular",
								size = 16.0,
							},
							color = is_focused and colors.text or colors.overlay0,
						},
					})
				else
					ws_groups[w].icons[i]:set({ drawing = false })
				end
			end
		else
			ws_groups[w].pill:set({ drawing = false })
			for i = 1, MAX_WINDOWS_PER_WS do
				ws_groups[w].icons[i]:set({ drawing = false })
			end
		end
	end
end

-- Single combined shell command (1 process instead of 3 sequential ones)
local QUERY_CMD = "echo '---WINDOWS---'; "
	.. "aerospace list-windows --all --format '%{workspace}|||%{app-name}' 2>/dev/null; "
	.. "echo '---FOCUSED_WS---'; "
	.. "aerospace list-workspaces --focused 2>/dev/null; "
	.. "echo '---FOCUSED_APP---'; "
	.. "aerospace list-windows --focused --format '%{app-name}' 2>/dev/null"

-- Parse the combined output into its 3 sections
local function parse_combined(raw)
	local windows_block = ""
	local focused_ws = ""
	local focused_app = ""

	local section = nil
	for line in raw:gmatch("[^\r\n]+") do
		if line == "---WINDOWS---" then
			section = "w"
		elseif line == "---FOCUSED_WS---" then
			section = "fw"
		elseif line == "---FOCUSED_APP---" then
			section = "fa"
		elseif section == "w" then
			windows_block = windows_block .. line .. "\n"
		elseif section == "fw" then
			focused_ws = line:match("^%s*(.-)%s*$") or ""
		elseif section == "fa" then
			focused_app = line:match("^%s*(.-)%s*$") or ""
		end
	end

	return windows_block, focused_ws, focused_app
end

-- Synchronous update (used at startup)
local function update_display_sync()
	local p = io.popen(QUERY_CMD)
	local raw = p and p:read("*a") or ""
	if p then
		p:close()
	end

	local windows_block, focused_ws, focused_app = parse_combined(raw)
	local workspaces, ws_order = parse_all_windows(windows_block)
	ensure_focused(workspaces, ws_order, focused_ws)
	render(workspaces, ws_order, focused_ws, focused_app)
end

-- Async update (used in event callbacks — single exec, no nesting)
local function update_display_async()
	if _G.SKETCHYBAR_SUSPENDED then
		return
	end

	sbar.exec(QUERY_CMD, function(raw)
		local output = tostring(raw or "")
		local windows_block, focused_ws, focused_app = parse_combined(output)
		local workspaces, ws_order = parse_all_windows(windows_block)
		ensure_focused(workspaces, ws_order, focused_ws)
		render(workspaces, ws_order, focused_ws, focused_app)
	end)
end

update_display_sync()

ws_groups[1].pill:subscribe("aerospace_workspace_change", function(_)
	update_display_async()
end)

ws_groups[1].pill:subscribe("front_app_switched", function(_)
	update_display_async()
end)

local poller = sbar.add("item", "aerospace.poller", {
	drawing = false,
	update_freq = 0,
})
poller:subscribe("routine", function(_)
	update_display_async()
end)
