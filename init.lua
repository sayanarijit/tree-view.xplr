---@diagnostic disable
local xplr = xplr
---@diagnostic enable

local state = {
  tree = {},
  pwd = "",
  focus = 0,
  is_layout_active = false,
  fullscreen = false,
}

local Expansion = {
  OPEN = "▼",
  CLOSED = "▶",
  DOT = "•",
}

local function new_branch(path, nodes, is_expanded)
  if is_expanded == nil then
    is_expanded = false
  end
  nodes = nodes or {}
  local modified = nil
  local node = xplr.util.node(path)
  if node then
    modified = node.last_modified
  end
  return {
    name = xplr.util.basename(path) or "/",
    path = path,
    node = node,
    nodes = nodes,
    expansion = Expansion.CLOSED,
    depth = #xplr.util.path_split(path) - 1,
    modified = modified,
  }
end

local function explore(path, explorer_config)
  local nodes = xplr.util.explore(path, explorer_config)
  state.tree[path] = new_branch(path, nodes)
  for _, node in ipairs(nodes) do
    if node.is_dir then
      if state.tree[node.absolute_path] == nil then
        state.tree[node.absolute_path] = new_branch(node.absolute_path, {}, false)
      end
    end
  end
end

local function expand(path, explorer_config)
  local modified = nil
  local node = xplr.util.node(path)

  if node then
    modified = node.last_modified
  end

  while true do
    if state.tree[path] == nil or modified ~= state.tree[path].last_modified then
      explore(path, explorer_config)
    end
    state.tree[path].expansion = Expansion.OPEN
    if path == "/" then
      break
    end
    path = xplr.util.dirname(path)
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

local function list_dfs(path)
  local branch = state.tree[path]
  if branch == nil then
    return {}
  end

  local item = {
    name = branch.name,
    path = branch.path,
    node = branch.node,
    expansion = branch.expansion,
    total = #branch.nodes,
    padding = string.rep(" ", branch.depth),
  }

  local items = { item }

  if branch.expansion == Expansion.OPEN then
    for _, n in ipairs(branch.nodes) do
      if n.is_dir then
        local items_ = list_dfs(n.absolute_path)
        for _, c in ipairs(items_) do
          table.insert(items, c)
        end
      else
        table.insert(items, {
          name = n.relative_path,
          path = n.absolute_path,
          expansion = Expansion.DOT,
          total = 0,
          padding = string.rep(" ", branch.depth + 1),
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

local function render(ctx)
  state.pwd = ctx.app.pwd
  expand(state.pwd, ctx.app.explorer_config)

  local focused_path = state.pwd
  if ctx.app.focused_node then
    focused_path = ctx.app.focused_node.absolute_path
  end

  local lines = list_dfs("/")

  local body = {}
  for i, line in ipairs(lines) do
    local l = line.path
    if line.path ~= "/" then
      l = " " .. line.expansion .. " " .. render_node(line.node)
    end

    l = l .. " "

    if focused_path and focused_path == line.path then
      if focused_path == state.pwd then
        l = l .. xplr.util.paint(" (empty) ", { add_modifiers = { "Reversed" } })
      else
        l = xplr.util.paint(l, { add_modifiers = { "Reversed" } })
      end
      state.focus = i - 1
    end

    if line.expansion == Expansion.OPEN then
      l = l .. "(" .. tostring(line.total) .. ")"
    end

    table.insert(body, line.padding .. l)
  end

  if state.focus > 0 then
    body = offset(body, ctx.layout_size.height)
  end

  return {
    CustomList = {
      ui = { title = { format = " " .. focused_path .. " " } },
      body = body,
    },
  }
end

local function toggle(app)
  if not app.focused_node then
    return
  end

  if not app.focused_node.is_dir then
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
  elseif state.fullscreen then
    msgs = {
      { SwitchLayoutCustom = "tree_view_fullscreen" },
    }
  else
    msgs = {
      { SwitchLayoutCustom = "tree_view" },
    }
  end
  state.is_layout_active = not state.is_layout_active
  return msgs
end

xplr.fn.custom.tree_view = {
  render = render,
  toggle = toggle,
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

  args.toggle_layout_mode = "default"
  args.toggle_layout_key = "esc"

  args.toggle_expansion_mode = "default"
  args.toggle_expansion_key = "o"

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
end

return { setup = setup, render_node = render_node }
