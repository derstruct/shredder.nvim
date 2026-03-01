local utils = require("shredder.utils")

local function log(m)
	-- vim.notify(m, vim.log.levels.INFO)
end

local M = {
	id = vim.api.nvim_get_current_tabpage()
}

---@type table<integer, boolean>
local floating_buffers = {}

---@class Buf
---@field id integer
---@field win integer | nil
---@type Buf[]
local buffers = {}

---@type integer | nil
local filler = nil

---@type integer | nil
local current_win = nil

---@class Panel
---@field buf Buf | nil
---@field pending boolean
---@type Panel
local panel = {
	pending = true,
}

local function panel_validate()
	if panel.buf == nil then
		return
	end
	if not vim.api.nvim_buf_is_valid(panel.buf.id) then
		if vim.api.nvim_win_is_valid(panel.buf.win) then
			vim.api.nvim_win_close(panel.buf.win, true)
		end
		panel.buf = nil
		return
	end
	if not vim.api.nvim_win_is_valid(panel.buf.win) then
		vim.api.nvim_buf_delete(panel.buf.id, { force = true })
		panel.buf = nil
		return
	end
end


local function get_current()
	if current_win == nil then
		return nil
	end
	for index, buf in ipairs(buffers) do
		if buf.win == current_win then
			return index
		end
	end
end


local ns = vim.api.nvim_create_namespace("shredder:active")
local function panel_redraw()
	if panel.buf == nil then
		return
	end
	vim.api.nvim_win_set_width(panel.buf.win, utils.get_width())
	local buf = vim.bo[panel.buf.id]
	buf.modifiable = true
	local row = 0
	vim.api.nvim_buf_set_lines(panel.buf.id, 0, -1, false, {})
	for _, opened_buf in ipairs(buffers) do
		local name, path = utils.display_path(vim.api.nvim_buf_get_name(opened_buf.id))
		local opts = {
			virt_lines = {
				{ { path, "NonText" } },
			},
			virt_lines_above = false,
		}
		if opened_buf.win ~= nil and opened_buf.win ~= 0 then
			opts.line_hl_group = "CursorLine"
			if opened_buf.win == current_win then
				name = "▎" .. name
			end
		end
		vim.api.nvim_buf_set_lines(panel.buf.id, row, row + 1, false, { name })
		vim.api.nvim_buf_set_extmark(panel.buf.id, ns, row, 0, opts)
		row = row + 1
	end
	buf.modifiable = false
end

---@class WindowDefaults
---@field number boolean
---@field signcolumn string
---@field relativenumber boolean
---@field numberwidth integer
---@field wrap boolean
---@field winfixwidth boolean
---@type WindowDefaults | nil
local defaults = nil


local function save_defaults(win_id)
	if defaults ~= nil then
		return
	end
	local win = vim.wo[win_id]
	defaults = {
		number = win.number,
		signcolumn = win.signcolumn,
		relativenumber = win.relativenumber,
		numberwidth = win.numberwidth,
		wrap = win.wrap,
		winfixwidth = win.winfixwidth,
	}
end

local function apply_defaults(win_id)
	local win = vim.wo[win_id]
	win.number = defaults.number
	win.signcolumn = defaults.signcolumn
	win.relativenumber = defaults.relativenumber
	win.numberwidth = defaults.numberwidth
	win.wrap = defaults.wrap
	win.winfixwidth = defaults.winfixwidth
end

local function panel_open()
	local current = vim.api.nvim_get_current_win()
	local buf_id = vim.api.nvim_create_buf(false, true)
	local buf = vim.bo[buf_id]
	buf.buftype = "nofile"
	buf.bufhidden = "wipe"
	buf.swapfile = false
	buf.modifiable = false
	buf.undofile = false
	vim.cmd("topleft vsplit")
	local win_id = vim.api.nvim_get_current_win()
	save_defaults(win_id)
	local win = vim.wo[win_id]
	win.number = true
	win.signcolumn = 'no'
	win.relativenumber = false
	win.numberwidth = 3
	win.signcolumn = "no"
	win.wrap = false
	win.winfixwidth = true
	vim.api.nvim_win_set_buf(win_id, buf_id)
	vim.api.nvim_set_option_value("winfixbuf", true, { win = win_id })
	vim.api.nvim_win_set_width(win_id, utils.get_width())
	vim.api.nvim_set_current_win(current)
	panel = {
		buf = {
			id = buf_id,
			win = win_id,
		},
		pending = false,
	}
end



local function panel_close()
	if panel.buf == nil then
		return
	end
	if vim.api.nvim_win_is_valid(panel.buf.win) then
		vim.api.nvim_win_close(panel.buf.win, true)
	end
	if vim.api.nvim_buf_is_valid(panel.buf.id) then
		vim.api.nvim_buf_delete(panel.buf.id, { force = true })
	end
	panel.buf = nil
	panel.pending = false
end

---@paran buf integer
---@returns integer | nil
local function panel_split(buf)
	if panel.buf == nil then
		return
	end
	local current = vim.api.nvim_get_current_win()
	local wins = {}
	for _, buf in ipairs(buffers) do
		if buf.win ~= nil then
			wins[buf.win] = true
		end
	end
	for _, win_id in ipairs(vim.api.nvim_tabpage_list_wins(M.id)) do
		if wins[win_id] == true then
			goto cont
		end
		if utils.win_is_floating(win_id) then
			goto cont
		end
		local buf_id = vim.api.nvim_win_get_buf(win_id)
		if vim.bo[buf_id].buftype ~= "" then
			goto cont
		end
		if vim.api.nvim_buf_get_name(buf_id) ~= "" then
			goto cont
		end
		vim.api.nvim_win_set_buf(win_id, buf)
		if current == panel.buf.win then
			vim.api.nvim_set_current_win(win_id)
		end
		do
			return win_id
		end
		::cont::
	end
	vim.api.nvim_set_current_win(panel.buf.win)
	vim.cmd("rightbelow vsplit")
	local win_id = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(win_id, buf)
	apply_defaults(win_id)
	if current ~= panel.buf.win then
		vim.api.nvim_set_current_win(current)
	end
	return win_id
end


local function buffers_sync()
	local wins = {}
	for _, win_id in ipairs(vim.api.nvim_tabpage_list_wins(M.id)) do
		local buf_id = vim.api.nvim_win_get_buf(win_id)
		wins[buf_id] = win_id
		if floating_buffers[buf_id] then
			table.insert(buffers, {
				id = buf_id,
			})
		end
	end
	local new_floating = {}
	local new_buffers = {}
	local current_set = false
	local current_found = true
	local current = vim.api.nvim_get_current_win()
	for _, buf in ipairs(buffers) do
		if not utils.buffer_is_valid(buf.id) then
			log("invalid " .. buf.id)
			goto cont
		end
		local win = wins[buf.id]
		if win ~= nil and utils.win_is_floating(win) then
			new_floating[buf.id] = true
			log("floating " .. buf.id)
			goto cont
		end
		if win ~= nil then
			if win == current then
				current_set = true
			elseif current_win ~= nil and current_win == win then
				current_found = true
			end
			filler = nil
		end
		log("adding " .. buf.id)
		table.insert(new_buffers, {
			id = buf.id,
			win = win,
		})
		::cont::
	end
	if current_set then
		current_win = current
	elseif not current_found then
		current_win = nil
	end
	floating_buffers = new_floating
	buffers = new_buffers
end

local function panel_sync()
	panel_validate()
	if #buffers <= 1 then
		log("sync no bufs to show")
		if panel.buf == nil then
			return
		end
		panel_close()
		panel.pending = true
		return
	end
	if panel.pending == true then
		local current = vim.api.nvim_get_current_win()
		if utils.win_is_floating(current) then
			return
		end
		panel_open()
	end
	panel_redraw()
end

local function sync()
	buffers_sync()
	panel_sync()
end

function M.on_win_closed(id)
	local seen = false
	for _, buf in ipairs(buffers) do
		if buf.win == nil then
			goto cont
		end
		if buf.win == id then
			buf.win = 0
			goto cont
		end
		seen = true
		::cont::
	end
	if seen then
		return
	end
	if filler == id then
		filler = nil
	end
	if filler ~= nil and vim.api.nvim_win_is_valid(filler) then
		return
	end
	if #buffers == 1 then
		panel_split(buffers[1].id)
		sync()
		return
	end
	local next_id = vim.api.nvim_create_buf(false, true)
	filler = panel_split(next_id)
	panel_sync()
end

function M.on_tab_closed(id)
	for _, buf in ipairs(buffers) do
		if vim.api.nvim_buf_is_valid(buf.id) then
			vim.api.nvim_buf_delete(buf.id, { force = true })
		end
	end
	buffers = {}
end

function M.sync()
	sync()
end

function M.toggle()
	if panel.buf == nil then
		panel.pending = true
		sync()
		return
	end
	panel_close()
end

---@param id integer
function M.on_buf_hide(id)
	if panel.buf ~= nil and panel.buf.id == id then
		panel_close()
		return
	end
	log("hide buf " .. id)
end

---@param id integer
function M.on_buf_add(id)
	table.insert(buffers, {
		id = id,
	})
	sync()
end

---@param id integer
function M.on_buf_delete(id)
	if panel.buf ~= nil and panel.buf.id == id then
		panel_close()
		return
	end
	local next = nil
	for index, buf in ipairs(buffers) do
		if buf.id == id then
			table.remove(buffers, index)
			if buf.win ~= nil and filler ~= nil and vim.api.nvim_win_is_valid(filler) then
				if next == nil then
					next = buffers[1]
				end
				if next ~= nil then
					vim.api.nvim_win_set_buf(filler, next.id)
				end
			end
			sync()
			return
		end
		next = buf
	end
end

function M.list(a, b)
	local list = {}
	for _, buf in ipairs(buffers) do
		table.insert(list, buf.id)
	end
	return list
end

---@param a integer
---@param b integer
---@return string | nil
function M.swap(a, b)
	if a == b then
		return
	end
	if a > #buffers or a < 1 then
		return "bad index " .. a
	end
	if b > #buffers or b < 1 then
		return "bad index" .. b
	end
	buffers[a], buffers[b] = buffers[b], buffers[a]
	sync()
end

---@param source integer
---@param target integer
---@return string | nil
function M.move_to(source, target)
	if source == target then
		return
	end
	if source > #buffers or source < 1 then
		return "bad index " .. source
	end
	if target > #buffers or target < 1 then
		return "bad index" .. target
	end
	local buf = buffers[source]
	table.remove(buffers, source)
	table.insert(buffers, target, buf)
	sync()
end

function M.current()
	return get_current()
end

function M.current_buffer()
	return M.buffer(M.current())
end

function M.buffer(index)
	if index == nil then
		return nil
	end
	local buf = buffers[index]
	if buf == nil then
		return nil
	end
	return buf.id
end

function M.length()
	return #buffers
end

---@param index integer
---@return string | nil
function M.switch_to(index)
	local buf = buffers[index]

	if buf == nil then
		return "no buffer #" .. index
	end

	if buf.win ~= nil then
		if buf.win == vim.api.nvim_get_current_win() then
			return
		end
		vim.api.nvim_set_current_win(buf.win)
		sync()
		return
	end

	if filler ~= nil then
		if vim.api.nvim_win_is_valid(filler) then
			vim.api.nvim_win_set_buf(filler, buf.id)
			sync()
			return
		end
	end

	if current_win ~= nil then
		vim.api.nvim_win_set_buf(current_win, buf.id)
		sync()
		return
	end

	for _, other_buf in ipairs(buffers) do
		if other_buf.win ~= nil then
			vim.api.nvim_win_set_buf(other_buf.win, buf.id)
			sync()
			return
		end
	end
	panel_split(buf.id)
	sync()
end

return M
