local M = {
}


local width = 20

function M.set_width(w)
	width = w
end

function M.get_width()
	return width
end

---@param win integer
---@return boolean
function M.win_is_floating(win)
	local cfg = vim.api.nvim_win_get_config(win or 0)
	return cfg.relative ~= ""
end


---@param id integer
---@return boolean
function M.buffer_is_valid(id)
	if not vim.api.nvim_buf_is_valid(id) then
		return false
	end
	if not vim.bo[id].buflisted then
		return false
	end
	return true
end

local event_guard = false
---@param f function()
function M.guard_event(f)
	if event_guard then
		return
	end
	event_guard = true
	f()
	event_guard = false
end
---
---@param p string
---@return string, string
function M.display_path(p)
	local sep = package.config:sub(1, 1) -- '/' or '\\'
	local sep_pat = sep:gsub("(%p)", "%%%1")
	local parts_pat = ("[^%s]+"):format(sep_pat)

	local parts = {}
	for part in p:gmatch(parts_pat) do
		parts[#parts + 1] = part
	end

	for i = 1, math.floor(#parts / 2) do
		parts[i], parts[#parts - i + 1] = parts[#parts - i + 1], parts[i]
	end
	local rest = vim.list_slice(parts, 2)
	return parts[1], table.concat(rest, '\\')
end

return M
