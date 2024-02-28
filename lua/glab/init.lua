local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local utils = require("telescope.utils")
local curl = require("plenary.curl")
local Git = require("lazy.manage.git")
local state = require("glab.state")

local M = {}

M.setup = function(args)
	if args == nil then
		args = {}
	end
	state.GITLAB_URL = args.GITLAB_URL or state.GITLAB_URL
	state.GITLAB_TOKEN = args.GITLAB_TOKEN or os.getenv("GITLAB_TOKEN")
end

local get_project_path = function()
	local url = Git.get_origin(".")
	if url:find("git@") then
		return string.match(url, ":(.-).git$")
	end
	return string.match(url, "[a-z]/(.-).git$")
end

M.browse = function(option, get_selection)
	get_selection = get_selection or false
	local path = option
	if option == "current_branch" then
		local result, _ = utils.get_os_command_output({ "git", "branch", "--show-current" }, ".")
		path = result[1]
	elseif option == "current_commit" then
		local result, _ = utils.get_os_command_output({ "git", "rev-parse", "--short", "HEAD" }, ".")
		path = result[1]
	end
	local line_nums = ""
	if get_selection then
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", false, true, true), "nx", false) -- Need to escape visual mode for marks to refresh
		local from = vim.api.nvim_buf_get_mark(0, "<")
		local to = vim.api.nvim_buf_get_mark(0, ">")
		line_nums = "\\#L" .. from[1] .. "-" .. to[1]
	end

	vim.cmd(
		"!open '"
			.. state.GITLAB_URL
			.. "/"
			.. get_project_path()
			.. "/-/blob/"
			.. path
			.. "/"
			.. vim.fn.expand("%:.")
			.. line_nums
			.. "'"
	)
end

M.checkout = function()
	local json = {
		query = 'query { project(fullPath: "'
			.. get_project_path()
			.. '") { mergeRequests(state: opened) { nodes { reference title sourceBranch }}}}',
	}
	local post_res = curl.post(state.GITLAB_URL .. "/api/graphql", {
		accept = "application/json",
		body = vim.fn.json_encode(json),
		headers = {
			content_type = "application/json",
			authorization = "Bearer " .. state.GITLAB_TOKEN,
		},
	})

	local nodes = vim.fn.json_decode(post_res.body).data.project.mergeRequests.nodes
	local list = { { "Check out master", "master" } }
	for i, node in ipairs(nodes) do
		table.insert(
			list,
			i,
			{ string.format("%s: %s", string.gsub(node.reference, "!", ""), node.title), node.sourceBranch }
		)
	end

	local branch_picker = function(opts)
		opts = opts or {}
		pickers
			.new(opts, {
				prompt_title = "Checkout merge request",

				finder = finders.new_table({
					results = list,
					entry_maker = function(entry)
						return {
							value = entry[2],
							display = entry[1],
							ordinal = entry[1],
						}
					end,
				}),
				sorter = conf.generic_sorter(opts),
				attach_mappings = function(prompt_bufnr, map)
					actions.select_default:replace(actions.git_checkout)
					return true
				end,
			})
			:find()
	end

	-- to execute the function
	branch_picker(require("telescope.themes").get_dropdown({}))
end

return M
