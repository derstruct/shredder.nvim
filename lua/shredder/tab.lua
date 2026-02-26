
local utils = require("shredder.utils")

local M = {
	id = vim.api.nvim_get_current_tabpage()
}

---@class Buf
---@field id integer
---@field win integer | nil
---@type Buf[]
local buffers = {}

---@class Panel
---@field buf Buf | nil
---@field pending boolean
---@type Panel
local panel = {
	pending = true,
}

local ns = vim.api.nvim_create_namespace("shredder:active")
local function panel_redraw()
	if panel.buf == nil then
		return
	end
	vim.api.nvim_win_set_width(panel.buf.win, utils.get_width())
	local current = vim.api.nvim_get_current_win()
	local buf = vim.bo[panel.buf.id]
	buf.modifiable = true
	local row = 0
	local count_visible = 0
	for _, opened_buf in ipairs(buffers) do
		if opened_buf.win ~= nil then
			count_visible = count_visible + 1
		end
	end
	vim.api.nvim_buf_set_lines(panel.buf.id, 0, -1, false, {})
	for _, opened_buf in ipairs(buffers) do
		local name, path = utils.display_path(vim.api.nvim_buf_get_name(opened_buf.id))
		vim.api.nvim_buf_set_lines(panel.buf.id, row, row + 1, false, { name })
		local opts = {
			virt_lines = {
				{ { path, "NonText" } },
			},
			virt_lines_above = false, -- false = below, true = above
		}
		if opened_buf.win ~= nil then
			opts.line_hl_group = "CursorLine"
		end
		if count_visible > 1 and opened_buf.win == current then
			opts.line_hl_group = "Visual"
		end
		vim.api.nvim_buf_set_extmark(panel.buf.id, ns, row, 0, opts)
		row = row + 1
	end
	buf.modifiable = false
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
	local win = vim.wo[win_id]
	win.number = true
	win.relativenumber = false
	win.signcolumn = "no"
	win.wrap = false
	vim.api.nvim_win_set_buf(win_id, buf_id)
	vim.api.nvim_set_option_value("winfixbuf", true, { win = win_id })
	vim.api.nvim_win_set_width(win_id, utils.get_width())
	win.winfixwidth = true
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
	vim.api.nvim_set_current_win(panel.buf.win)
	vim.cmd("rightbelow vsplit")
	local win_id = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(win_id, buf)
	if current ~= panel.buf.win then
		vim.api.nvim_set_current_win(current)
	end
	return win_id
end


local function panel_sync()
	do
		local wins = {}
		for _, win_id in ipairs(vim.api.nvim_tabpage_list_wins(M.id)) do
			local buf_id = vim.api.nvim_win_get_buf(win_id)
			wins[buf_id] = win_id
		end
		local new_buffers = {}
		for _, buf in ipairs(buffers) do
			if vim.api.nvim_buf_is_valid(buf.id) then
				table.insert(new_buffers, {
					id = buf.id,
					win = wins[buf.id],
				})
			end
		end
		buffers = new_buffers
	end
	if #buffers <= 1 then
		if panel.pending then
			return
		end
		panel_close()
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


---@param id integer
function M.on_tab_enter(id)
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

function M.on_win_enter()
	panel_redraw()
end

---@param id integer
function M.on_win_closed(id)
	local ok = false
	local found = nil
	for _, buf in ipairs(buffers) do
		if buf.win == nil then
			goto cont
		end
		if buf.win == id then
			found = buf
			goto cont
		end
		if not vim.api.nvim_win_is_valid(buf.win) then
			goto cont
		end
		ok = true
		::cont::
		buf.win = nil
	end
	if ok then
		return
	end
	if found ~= nil and vim.api.nvim_buf_is_valid(found.id) then
		panel_split(found.id)
		panel_redraw()
	end
end

---@param id integer
function M.on_buf_enter(id)
	if panel.buf ~= nil and panel.buf.id == id then
		return
	end
	if not utils.buffer_is_valid(id) then
		return
	end
	local win = vim.api.nvim_get_current_win()
	if utils.win_is_floating(win) then
		return
	end
	for _, buf in ipairs(buffers) do
		if buf.id == id then
			goto sync
		end
	end
	table.insert(buffers, {
		id = id,
	})
	::sync::
	panel_sync()
end

---@param win integer
---@param prev Buf
local function fix_current(win, prev)
	for _, buf in ipairs(buffers) do
		if buf.win ~= nil then
			return
		end
	end
	if prev == nil then
		prev = buffers[1]
	end
	if prev == nil then
		return
	end
	if win ~= nil and vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_win_set_buf(win, prev.id)
		return
	end
	panel_split(prev.id)
end



function M.toggle()
	if panel.buf == nil then
		panel.pending = true
		panel_sync()
		return
	end
	panel_close()
end

---@param id integer
function M.on_buf_hide(id)
	if panel.buf ~= nil and panel.buf.id == id then
		panel_close()
	end
end

---@param id integer
function M.on_buf_delete(id)
	if panel.buf ~= nil and panel.buf.id == id then
		panel_close()
		return
	end
	local prev = nil
	local win = nil
	for index, buf in ipairs(buffers) do
		if buf.id == id then
			win = buf.win
			table.remove(buffers, index)
			goto cont
		end
		prev = buf
	end
	do
		return
	end
	::cont::
	fix_current(win, prev)
	panel_sync()
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
	panel_sync()
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
	if source < target then
		target = target - 1
	end
	local buf = buffers[source]
	table.remove(buffers, source)
	table.insert(buffers, target, buf)
	panel_sync()
end

function M.current()
	local current = vim.api.nvim_get_current_win()
	for index, buf in ipairs(buffers) do
		if buf.win ~= nil and buf.win == current then
			return index
		end
	end
	return nil
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

	local current = vim.api.nvim_get_current_win()
	if buf.win ~= nil then
		if buf.win == current then
			return
		end
		vim.api.nvim_set_current_win(buf.win)
		panel_sync()
		return
	end

	local switch_buf = nil
	---
	---@type Buf[]
	local visible_buffers = {}
	for _, other_buf in ipairs(buffers) do
		if other_buf.win == nil then
			goto cont
		end
		if other_buf.win == current then
			switch_buf = other_buf
			break
		end
		table.insert(visible_buffers, other_buf)
		::cont::
	end

	if switch_buf == nil and #visible_buffers == 1 then
		switch_buf = visible_buffers[1]
	end

	if switch_buf == nil and #visible_buffers ~= 1 then
		for _, it in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
			for _, visible_buf in ipairs(visible_buffers) do
				if visible_buf.id == it.bufnr then
					switch_buf = visible_buf
					goto brk
				end
			end
		end
		switch_buf = visible_buffers[1]
		::brk::
	end
	if switch_buf ~= nil then
		vim.api.nvim_win_set_buf(switch_buf.win, buf.id)
	else
		panel_split(buf.id)
	end
	panel_sync()
end

return M
