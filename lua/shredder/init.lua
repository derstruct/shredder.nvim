local M = {}

local man = require("shredder.man")
local utils = require("shredder.utils")

local function log(args)
	local ev = args and args.event or "?"
	local buf = (args and type(args.buf) == "number") and args.buf or nil
	local msg = ("autocmd %s%s"):format(ev, buf and (" buf=" .. buf) or "")
	-- vim.notify(msg, vim.log.levels.DEBUG)
end

---@param target string | integer | nil
---@param force boolean
---@return string | nil
local function tabclose(target, force)
	local command = "tabclose"
	if force then
		command = command .. "!"
	end
	if target ~= nil then
		command = command .. " " .. target
	end
	local ok, err = pcall(vim.cmd, command)
	if not ok then
		return err
	end
end

---@param buf integer
---@param force boolean
---@return string | nil
local function wipe_buf(buf, force)
	local command = "bw"
	if force then
		command = command .. "!"
	end
	local ok, err = pcall(vim.cmd, command .. " " .. buf)
	if not ok then
		return err
	end
end

function M.setup(opts)
	local group = vim.api.nvim_create_augroup("Shredder", { clear = true })
	if opts.width ~= nil then
		utils.set_width(opts.width)
	end


	vim.api.nvim_create_autocmd({ "BufDelete" }, {
		group = group,
		callback = function(args)
			log(args)
			local id = args.buf
			man.guard(function(tab)
				tab.on_buf_delete(id)
			end)
		end,
	})
	vim.api.nvim_create_autocmd("BufAdd", {
		group = group,
		callback = function(args)
			log(args)
			local id = args.buf
			vim.schedule(function()
				man.guard(function(tab)
					tab.on_buf_add(id)
				end)
			end)
		end,
	})

	vim.api.nvim_create_autocmd("WinClosed", {
		group = group,
		callback = function(args)
			log(args)
			local id = tonumber(args.match)
			man.guard(function(tab)
				tab.on_win_closed(id)
			end)
		end
	})

	vim.api.nvim_create_autocmd(
		{ "TabEnter", "WinEnter", "BufWinEnter", },
		{
			group = group,
			callback = function(args)
				log(args)
				vim.schedule(function()
					man.guard(function(tab)
						tab.sync()
					end)
				end)
			end
		})

	vim.api.nvim_create_autocmd("TabClosed", {
		group = group,
		callback = function(args)
			man.close_tab()
		end,
	})


	vim.api.nvim_create_user_command("Shoggle", function()
		man.guard(function(tab)
			tab.toggle()
		end)
	end, {})
	--[[
	vim.api.nvim_create_user_command("Shoggle", function()
		M.toggle()
	end, {})

	vim.api.nvim_create_user_command("Shwitch", function(opts)
		local index = tonumber(opts.args)
		if not index or index % 1 ~= 0 then
			vim.notify("Shwitch: expected an integer.", vim.log.levels.ERROR)
			return
		end

		M.switch(index)
	end, {
		nargs = 1,
		desc = "Takes an integer.",
	})
	--]]

	vim.api.nvim_create_user_command("Shred", function()
		M.shred()
	end, {}) --]]
end

function M.shred()
	local state = {
		Init = 1,
		Switch = 2,
		MoveInit = 3,
		Move = 4,
		WipeInit = 5,
		Wipe = 6,
	}
	local state_msg = { "Sh", "Switch", "Move", "Move", "Delete", "Delete" }
	local force = false
	local index = 0
	local tabs = false
	local s = state.Init
	local err = nil
	local function msg()
		local m = state_msg[s]
		if tabs then
			m = "Tab " .. m
		end
		if force then
			m = m .. "!"
		end
		m = m .. "..."

		vim.api.nvim_echo({ { m, "None" } }, false, {})
		vim.cmd("redraw")
	end
	msg()
	while true do
		local ok, key = pcall(vim.fn.getcharstr)
		if not ok then
			break
		end
		local k = vim.fn.keytrans(key)
		if k == "<Esc>" then
			break
		end
		if k == "<CR>" then
			break
		end
		if k == " " then
			break
		end
		if s == state.Init then
			if k == "e" then
				s = state.Switch
				msg()
				goto number
			end
			if k == "t" then
				if tabs then
					vim.cmd("tabnew")
					break
				end
				tabs = true
				msg()
				goto continue
			end
			if k == "k" or k == "h" then
				if tabs then
					vim.cmd("tabp")
				else
					err = M.switch_up()
				end
				break
			end
			if k == "j" or k == "l" then
				if tabs then
					vim.cmd("tabn")
					break
				else
					err = M.switch_down()
				end
				break
			end
			if k == "m" then
				s = state.MoveInit
				msg()
				goto continue
			end
			if k == "d" then
				s = state.WipeInit
				msg()
				goto continue
			end
			local n = tonumber(k)
			if n ~= nil then
				s = state.Switch
				msg()
				goto number
			end
			err = "Unrecognized command"
			break
		end
		if s == state.MoveInit then
			if k == "e" then
				s = state.Move
				goto number
			end
			if k == "K" or k == "H" then
				if tabs then
					vim.cmd("tabmove 0")
					break
				else
					err = M.move_up(true)
				end
				break
			end
			if k == "J" or k == "L" then
				if tabs then
					vim.cmd("tabmove")
					break
				else
					err = M.move_down(true)
				end
				break
			end
			if k == "k" or k == "h" then
				if tabs then
					vim.cmd("tabmove -1")
					break
				else
					err = M.move_up(false)
				end
				break
			end
			if k == "j" or k == "l" then
				if tabs then
					vim.cmd("tabmove +1")
					break
				else
					err = M.move_down(false)
				end
				break
			end
			local n = tonumber(k)
			if n ~= nil then
				s = state.Move
				goto number
			end
			err = "Unrecognized command"
			break
		end
		if s == state.WipeInit then
			if k == "e" then
				s = state.Wipe
				goto number
			end
			if k == "!" then
				force = true
				msg()
				goto continue
			end
			if k == "d" then
				if tabs then
					err = tabclose(nil, force)
				else
					err = M.wipe_current(force)
				end
				break
			end
			if k == "k" or k == "h" then
				if tabs then
					local cur = vim.fn.tabpagenr()
					if cur > 1 then
						err = tabclose(cur - 1, force)
					end
				else
					err = M.wipe_up(force, false)
				end
				break
			end
			if k == "j" or k == "l" then
				if tabs then
					local cur = vim.fn.tabpagenr()
					local last = vim.fn.tabpagenr("$")
					if cur < last then
						err = tabclose(cur + 1, force)
					end
				else
					err = M.wipe_down(force, false)
				end
				break
			end
			if k == "K" or k == "H" then
				if tabs then
					err = tabclose(1, force)
				else
					err = M.wipe_up(force, true)
				end
				break
			end
			if k == "J" or k == "L" then
				if tabs then
					err = tabclose("$", force)
				else
					err = M.wipe_down(force, true)
				end
				break
			end
			local n = tonumber(k)
			if n ~= nil then
				s = state.Wipe
				goto number
			end
			err = "Unrecognized command"
			break
		end
		::number::
		if s == state.Switch or s == state.Move or s == state.Wipe then
			if k == "e" then
				index = index + 10
				goto continue
			end
			local n = tonumber(k)
			if n == nil then
				err = "Number is expected"
				break
			end
			index = index + n
			if index == 0 then
				break
			end
			if s == state.Switch then
				if tabs then
					vim.cmd("tabnext " .. index)
				else
					err = M.switch_to(index)
				end
			elseif s == state.Move then
				if tabs then
					vim.cmd("tabmove " .. (index - 1))
				else
					err = M.move_to(index)
				end
			else
				if tabs then
					err = tabclose(index, force)
				else
					err = M.wipe(index, force)
				end
			end
			break
		end
		::continue::
	end
	if err ~= nil then
		vim.api.nvim_echo({ { err, "ErrorMsg" } }, false, {})
		return
	end
	vim.api.nvim_echo({ { "", "None" } }, false, {})
	vim.cmd("redraw")
end

---@param index integer
---@return string | nil
function M.switch_to(index)
	local err = nil
	man.guard(function(tab)
		err = tab.switch_to(index)
	end)
	return err
end

---@return string | nil
function M.switch_up()
	local err = nil
	man.guard(function(tab)
		local index = tab.current()
		if index == nil then
			err = "current buffer not found"
			return
		end
		if index == 1 then
			return
		end
		err = tab.switch_to(index - 1)
	end)
	return err
end

---
---@return string | nil
function M.switch_down()
	local err = nil
	man.guard(function(tab)
		local index = tab.current()
		if index == nil then
			err = "current buffer not found"
			return
		end
		if index == tab.length() then
			return
		end
		err = tab.switch_to(index + 1)
	end)
	return err
end

---
---@param index integer
---@return string | nil
function M.move_to(index)
	local err = nil
	man.guard(function(tab)
		if index < 1 then
			index = 1
		end
		if index > tab.length() then
			index = tab.length()
		end
		local current_index = tab.current()
		if current_index == nil then
			err = "current buffer not found"
			return
		end
		err = tab.move_to(current_index, index)
	end)
	return err
end

---@param all boolean
---@return string | nil
function M.move_up(all)
	local err = nil
	man.guard(function(tab)
		local index = tab.current()
		if index == nil then
			err = "current buffer not found"
			return
		end
		if index == 1 then
			return
		end
		local target = index - 1
		if all then
			target = 1
		end
		err = tab.move_to(index, target)
	end)
	return err
end

---@param all boolean
---@return string | nil
function M.move_down(all)
	local err = nil
	man.guard(function(tab)
		local index = tab.current()
		if index == nil then
			err = "current buffer not found"
			return
		end
		if index == tab.length() then
			return
		end
		local target = index + 1
		if all then
			target = tab.length()
		end
		err = tab.move_to(index, target)
	end)
	return err
end

function M.close_tab(args)
	--close_tab()
end

---@param index integer | nil
---@param force boolean
---@return string | nil
function M.wipe(index, force, tab)
	tab = tab or man.tab()
	if index == nil then
		return "buffer not found"
	end
	local buf = tab.buffer(index)
	if buf == nil then
		return "buffer #" .. index .. " not found"
	end
	return wipe_buf(buf, force)
end

---
---@param force boolean
---@return string | nil
function M.wipe_current(force)
	local tab = man.tab()
	local current = tab.current()
	if current == nil then
		return "current buffer not found"
	end
	return M.wipe(current, force, tab)
end

---@param force boolean
---@return string | nil
function M.wipe_up(force, all)
	local tab = man.tab()
	local index = tab.current()
	if index == nil then
		return "current buffer not found"
	end
	if index == 1 then
		return
	end
	local first = index - 1
	if all then
		first = 1
	end
	local bufs = {}
	for i = first, index - 1 do
		local buf = tab.buffer(i)
		if buf == nil then
			return "buffer #" .. i .. " not found"
		end
		table.insert(bufs, buf)
	end
	for _, buf in ipairs(bufs) do
		local err = wipe_buf(buf, force)
		if err ~= nil then
			return err
		end
	end
end

---
---@param force boolean
---@param all boolean
---@return string | nil
function M.wipe_down(force, all)
	local tab = man.tab()
	local index = tab.current()
	if index == nil then
		return "current buffer not found"
	end
	if index == tab.length() then
		return
	end
	local last = index + 1
	if all then
		last = tab.length()
	end
	local bufs = {}
	for i = index + 1, last do
		local buf = tab.buffer(i)
		if buf == nil then
			return "buffer #" .. i .. " not found"
		end
		table.insert(bufs, buf)
	end
	for _, buf in ipairs(bufs) do
		local err = wipe_buf(buf, force)
		if err ~= nil then
			return err
		end
	end
end

function M.toggle()
	ctrl.toggle()
end

return M
