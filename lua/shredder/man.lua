local tabs = {}

local M = {}

local function new_tab()
	package.loaded["shredder.tab"] = nil
	return require("shredder.tab")
end


local guard = false
function M.guard(f)
	if guard then
		return
	end
	guard = true
	f(M.tab())
	guard = false
end

function M.close_tab()
	local valid = {}
	for _, tab_id in ipairs(vim.api.nvim_list_tabpages()) do
		valid[tab_id] = true
	end
	local new_tabs = {}
	for _, tab in ipairs(tabs) do
		if valid[tab.id] then
			table.insert(new_tabs, tab)
			goto cont
		end
		tab.on_tab_closed()
		::cont::
	end
	tabs = new_tabs
end

function M.tab()
	local tab_id = vim.api.nvim_get_current_tabpage()
	local current_tab = nil
	for _, tab in ipairs(tabs) do
		if tab.id == tab_id then
			current_tab = tab
			goto cont
		end
	end
	package.loaded["shredder.tab"] = nil
	current_tab = new_tab()
	table.insert(tabs, current_tab)
	::cont::
	return current_tab
end

return M
