---@diagnostic disable
local xplr = xplr
---@diagnostic enable

local state = {
  tree = {},
  pwd = "",
  root = "",
  focus = 0,
  is_layout_active = false,
  fullscreen = false,
  indent = "  ",
  is_selected = {},
}

local Expansion = {
  OPEN = "▼",
  CLOSED = "▶",
  NA = "•",
}

local Cursor = {
  FOCUS = "◀",
  SELECTION = "✓",
}

local function new_branch(path, nodes, explorer_config, all_expanded)
  local modified = nil
  local node = xplr.util.node(path)
  if node and nodes ~= nil then
    modified = node.last_modified
  end
  if explorer_config then
    explorer_config.searcher = nil
  end
  return {
    name = xplr.util.basename(path) or "/",
    path = path,
    node = node,
    nodes = nodes or {},
    expansion = Expansion.CLOSED,
    depth = #xplr.util.path_split(path) - 1,
    modified = modified,
    explorer_config = explorer_config,
    all_expanded = all_expanded or false,
  }
end

local function explore(path, explorer_config)
  local branch = state.tree[path]
  local nodes = xplr.util.explore(path, explorer_config)
  state.tree[path] =
      new_branch(path, nodes, explorer_config, branch and branch.all_expanded)
  for _, node in ipairs(nodes) do
    if node.is_dir then
      if state.tree[node.absolute_path] == nil then
        state.tree[node.absolute_path] = new_branch(node.absolute_path)
      end
    end
  end
end

local function expand(path, explorer_config)
  while true do
    explore(path, explorer_config)

    state.tree[path].expansion = Expansion.OPEN
    if path == state.root then
      break
    end
    path = xplr.util.dirname(path)
    explorer_config = (state.tree[path] or {}).explorer_config or explorer_config
  end
end

local function offset(listing, height)
  local h = height - 2
  local start = (state.focus - (state.focus % h))
  local result = {}
  for i = start + 1, start + h, 1 do
    table.insert(result, listing[i])
  end
  return result
end

local function list_dfs(path, ndepth)
  local branch = state.tree[path]
  if branch == nil then
    return {}
  end

  ndepth = ndepth or branch.depth

  local item = {
    name = branch.name,
    path = branch.path,
    node = branch.node,
    expansion = branch.expansion,
    total = #branch.nodes,
    padding = string.rep(state.indent, branch.depth - ndepth),
  }

  local items = { item }

  if branch.expansion == Expansion.OPEN then
    for _, n in ipairs(branch.nodes) do
      if n.is_dir then
        local items_ = list_dfs(n.absolute_path, ndepth)
        for _, c in ipairs(items_) do
          table.insert(items, c)
        end
      else
        table.insert(items, {
          name = n.relative_path,
          path = n.absolute_path,
          expansion = Expansion.NA,
          total = 0,
          padding = string.rep(state.indent, branch.depth - ndepth + 1),
          node = n,
        })
      end
    end
  end

  return items
end

local function render_node(node)
  local nl = xplr.util.paint("\\n", { add_modifiers = { "Italic", "Dim" } })
  local r = ""
  local style = xplr.util.lscolor(node.absolute_path)

  local rel = node.relative_path
  if node.is_dir then
    rel = rel .. "/"
  end
  r = r .. xplr.util.paint(xplr.util.shell_escape(rel), style)

  if node.is_symlink then
    r = r .. "-> "

    if node.is_broken then
      r = r .. "×"
    else
      local symlink_path = xplr.util.shorten(node.symlink.absolute_path)
      if node.symlink.is_dir then
        symlink_path = symlink_path .. "/"
      end
      r = r .. symlink_path:gsub("\n", nl)
    end
  end

  return r
end

local function common_parent(path1, path2)
  local p1 = xplr.util.path_split(path1)
  local p2 = xplr.util.path_split(path2)
  local common = {}

  for i, part in ipairs(p1) do
    if part == "/" then
      -- pass
    elseif p2[i] == part then
      table.insert(common, part)
    else
      break
    end
  end

  return "/" .. table.concat(common, "/")
end

local function render(ctx)
  state.pwd = ctx.app.pwd
  if ctx.app.vroot then
    state.root = ctx.app.vroot
  else
    state.root = ctx.app.initial_pwd
  end

  if
      state.pwd ~= state.root
      and string.sub(state.pwd, 1, #state.root + 1) ~= state.root .. "/"
  then
    state.root = common_parent(state.pwd, state.root)
  end

  state.is_selected = {}
  for _, sel in ipairs(ctx.app.selection) do
    state.is_selected[sel.absolute_path] = true
  end

  expand(state.pwd, ctx.app.explorer_config)

  local focused_path = state.pwd
  if ctx.app.focused_node then
    focused_path = ctx.app.focused_node.absolute_path
  end

  local lines = list_dfs(state.root)

  local body = {}
  for i, line in ipairs(lines) do
    local l = " " .. line.expansion
    if line.path == "/" then
      l = l .. " " .. line.path
    else
      l = l .. " " .. render_node(line.node)
    end

    if line.expansion == Expansion.OPEN then
      l = l .. " (" .. tostring(line.total) .. ")"
    end

    if state.is_selected[line.path] then
      l = xplr.util.paint(l, { add_modifiers = { "CrossedOut" } })
      l = l .. " " .. Cursor.SELECTION
    end

    if focused_path and focused_path == line.path then
      l = l .. " " .. Cursor.FOCUS .. " "

      if focused_path == state.pwd then
        l = l .. xplr.util.paint(" (empty)", { add_modifiers = { "Reversed" } })
      else
        l = xplr.util.paint(l, { add_modifiers = { "Reversed" } })
      end

      state.focus = i - 1
    end

    table.insert(body, line.padding .. l)
  end

  if state.focus > 0 then
    body = offset(body, ctx.layout_size.height)
  end

  local title = state.pwd
  if ctx.app.vroot then
    title = "vroot:/" .. string.sub(state.pwd, #ctx.app.vroot + 2)
  end
  title = " " .. title .. " (" .. tostring(#state.tree[state.pwd].nodes) .. ") "

  return {
    CustomList = {
      ui = { title = { format = title } },
      body = body,
    },
  }
end

local function toggle(app)
  if not app.focused_node or not app.focused_node.is_dir then
    return
  end

  local path = app.focused_node.absolute_path
  if state.tree[path] == nil then
    explore(path, app.explorer_config)
  end

  if state.tree[path].expansion == Expansion.CLOSED then
    expand(path, app.explorer_config)
  elseif state.tree[path].expansion == Expansion.OPEN then
    state.tree[path].expansion = Expansion.CLOSED
    state.tree[app.pwd].all_expanded = false
  end
end

local function close_all(app)
  for _, node in ipairs(app.directory_buffer.nodes) do
    if node.is_dir then
      state.tree[node.absolute_path].expansion = Expansion.CLOSED
    end
  end
  state.tree[app.pwd].all_expanded = false
end

local function open_all(app)
  for _, node in ipairs(app.directory_buffer.nodes) do
    if node.is_dir then
      expand(node.absolute_path, app.explorer_config)
    end
  end
  state.tree[app.pwd].all_expanded = true
end

local function toggle_all(app)
  if state.tree[app.pwd].all_expanded then
    close_all(app)
  else
    open_all(app)
  end
end

xplr.config.layouts.custom.tree_view_fullscreen = {
  Dynamic = "custom.tree_view.render",
}

xplr.config.layouts.custom.tree_view = xplr.util.layout_replace(
  xplr.config.layouts.builtin.default,
  "Table",
  xplr.config.layouts.custom.tree_view_fullscreen
)

local function toggle_layout(_)
  local msgs = {}
  if state.is_layout_active then
    msgs = {
      { SwitchLayoutBuiltin = "default" },
    }
    state.is_layout_active = false
  elseif state.fullscreen then
    msgs = {
      { SwitchLayoutCustom = "tree_view_fullscreen" },
    }
    state.is_layout_active = true
  else
    msgs = {
      { SwitchLayoutCustom = "tree_view" },
    }
    state.is_layout_active = true
  end
  return msgs
end

xplr.fn.custom.tree_view = {
  render = render,
  toggle = toggle,
  toggle_all = toggle_all,
  toggle_layout = toggle_layout,
}

local function setup(args)
  args = args or {}

  if args.fullscreen ~= nil then
    state.fullscreen = args.fullscreen
  end

  if args.as_default_layout == true then
    if state.fullscreen then
      xplr.config.layouts.builtin.default =
          xplr.config.layouts.custom.tree_view_fullscreen
    else
      xplr.config.layouts.builtin.default = xplr.config.layouts.custom.tree_view
    end
  end

  if args.as_initial_layout == true then
    if state.fullscreen then
      xplr.config.general.initial_layout = "tree_view_fullscreen"
    else
      xplr.config.general.initial_layout = "tree_view"
    end
    state.is_layout_active = true
  end

  if args.render_node ~= nil then
    render_node = args.render_node
  end

  args.mode = args.mode or "switch_layout"
  args.key = args.key or "T"

  args.toggle_layout_mode = args.toggle_layout_mode or "default"
  args.toggle_layout_key = args.toggle_layout_key or "esc"

  args.toggle_expansion_mode = args.toggle_expansion_mode or "default"
  args.toggle_expansion_key = args.toggle_expansion_key or "o"

  args.toggle_expansion_all_mode = args.toggle_expansion_all_mode or "default"
  args.toggle_expansion_all_key = args.toggle_expansion_all_key or "O"

  state.indent = args.indent or state.indent

  xplr.config.modes.builtin[args.mode].key_bindings.on_key[args.key] = {
    help = "tree view",
    messages = {
      "PopMode",
      { SwitchLayoutCustom = "tree_view" },
    },
  }

  xplr.config.modes.builtin[args.toggle_layout_mode].key_bindings.on_key[args.toggle_layout_key] =
  {
    help = "tree view",
    messages = {
      "PopMode",
      { CallLuaSilently = "custom.tree_view.toggle_layout" },
    },
  }

  xplr.config.modes.builtin[args.toggle_expansion_mode].key_bindings.on_key[args.toggle_expansion_key] =
  {
    help = "toggle expansion",
    messages = {
      "PopMode",
      { CallLuaSilently = "custom.tree_view.toggle" },
    },
  }

  xplr.config.modes.builtin[args.toggle_expansion_all_mode].key_bindings.on_key[args.toggle_expansion_all_key] =
  {
    help = "toggle all expansion",
    messages = {
      "PopMode",
      { CallLuaSilently = "custom.tree_view.toggle_all" },
    },
  }
end

return { setup = setup, render_node = render_node }
