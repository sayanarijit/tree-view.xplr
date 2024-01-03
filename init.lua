---@diagnostic disable
local xplr = xplr
local version = version
---@diagnostic enable

local xplrv = nil
if xplr.util and xplr.util.version then
  xplrv = xplr.util.version()
end

local does_support_deep_branch_navigation = xplrv
  and xplrv.major >= 0
  and xplrv.minor >= 21
  and xplrv.patch >= 4

local state = {
  tree = {},
  pwd = "",
  root = "",
  highlight = 0,
  is_layout_active = false,
  fullscreen = false,
  indent = "  ",
  is_selected = {},
  node_types = {},
  fallback_layout = "Table",
  fallback_threshold = nil,
  lines = {},
}

local Expansion = {
  OPEN = "▽",
  CLOSED = "▷",
  NA = "◦",
}

Expansion.decorate = function(self)
  if self == Expansion.OPEN then
    return Expansion.OPEN
  elseif self == Expansion.CLOSED then
    return " "
  else
    return " "
  end
end

Expansion.highlight = function(self)
  if self == Expansion.OPEN then
    return "▼"
  elseif self == Expansion.CLOSED then
    return "▶"
  else
    return "•"
  end
end

local Cursor = {
  FOCUS = "◀",
  SELECTION = "✓",
}

local function is_dir(n)
  return n.is_dir or (n.symlink and n.symlink.is_dir)
end

local function get_set_node_type(node)
  local nt = state.node_types[node.absolute_path]
  if not nt then
    nt = xplr.util.node_type(node)
    state.node_types[node.absolute_path] = nt
  end
  return nt
end

local function new_branch(node, nodes, explorer_config, all_expanded)
  local path = node
  if type(node) == "table" then
    path = node.absolute_path
  else
    node = xplr.util.node(path)
  end

  if node then
    local nt = get_set_node_type(node)
    node.meta = nt.meta
    node.style = nt.style
  end

  local fallback = false
  if nodes then
    if state.fallback_threshold and #nodes > state.fallback_threshold then
      fallback = true
    else
      for _, n in ipairs(nodes) do
        local nt = get_set_node_type(n)
        n.meta = nt.meta
        n.style = nt.style
      end
    end
  end

  if explorer_config then
    explorer_config.searcher = nil
  end

  return {
    name = node and node.relative_path or "/",
    path = path,
    node = node,
    nodes = nodes or {},
    expansion = Expansion.CLOSED,
    depth = #xplr.util.path_split(path) - 1,
    explorer_config = explorer_config,
    all_expanded = all_expanded or false,
    fallback = fallback,
  }
end

local function explore(path, explorer_config)
  local old_branch = state.tree[path]
  if old_branch and old_branch.fallback then
    return old_branch
  end
  local nodes = xplr.util.explore(path, explorer_config)
  local branch =
    new_branch(path, nodes, explorer_config, old_branch and old_branch.all_expanded)
  state.tree[path] = branch

  if not branch.fallback then
    for _, node in ipairs(nodes) do
      if is_dir(node) then
        if state.tree[node.absolute_path] == nil then
          state.tree[node.absolute_path] = new_branch(node)
        end
      end
    end
  end

  return branch
end

local function expand(path, explorer_config)
  while true do
    local branch = explore(path, explorer_config)
    if branch.fallback then
      return true
    end

    branch.expansion = Expansion.OPEN
    if path == state.root then
      break
    end
    path = xplr.util.dirname(path)
    explorer_config = (state.tree[path] or {}).explorer_config or explorer_config
  end

  return false
end

local function offset(listing, height)
  local h = height - 2
  local start = (state.highlight - (state.highlight % h))
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
      if is_dir(n) then
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
  if node.meta and node.meta.icon ~= nil then
    r = node.meta.icon .. " "
  end
  local style = xplr.util.lscolor(node.absolute_path)
  style = xplr.util.style_mix({ style, node.style })

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
      local symlink_path =
        xplr.util.shorten(node.symlink.absolute_path, { base = node.parent })
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

  local is_ok, fallback = pcall(expand, state.pwd, ctx.app.explorer_config)
  if not is_ok or fallback then
    return { CustomLayout = state.fallback_layout }
  end

  state.is_selected = {}
  for _, sel in ipairs(ctx.app.selection) do
    state.is_selected[sel.absolute_path] = true
  end

  local cursor_path = state.pwd
  if ctx.app.focused_node then
    cursor_path = ctx.app.focused_node.absolute_path
  end

  state.lines = list_dfs(state.root)

  local body = {}
  for i, line in ipairs(state.lines) do
    local is_highlighted = false
    local is_focused = false
    local exp_icon = Expansion.decorate(line.expansion)

    if cursor_path and cursor_path == line.path then
      is_highlighted = true
      if cursor_path ~= state.pwd then
        is_focused = true
        exp_icon = Expansion.highlight(line.expansion)
      end
    end

    local l = exp_icon
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

    if is_highlighted then
      if is_focused then
        l = xplr.util.paint(l, { add_modifiers = { "Bold" } })
      else
        l = l .. " " .. xplr.util.paint("(empty)", { add_modifiers = { "Dim" } })
      end

      l = l .. " " .. Cursor.FOCUS

      state.highlight = i - 1
    end

    table.insert(body, " " .. line.padding .. l)
  end

  if state.highlight > 0 then
    body = offset(body, ctx.layout_size.height)
  end

  local title = state.pwd
  if ctx.app.vroot then
    local rel = string.sub(state.pwd, #ctx.app.vroot + 1)
    if string.sub(rel, 1, 1) == "/" then
      rel = string.sub(rel, 2)
    end
    title = "vroot:/" .. rel
  end
  title = " " .. title .. " (" .. tostring(#state.tree[state.pwd].nodes) .. ") "

  return {
    CustomList = {
      ui = { title = { format = title } },
      body = body,
    },
  }
end

local function open(app)
  if not app.focused_node or not is_dir(app.focused_node) then
    return
  end
  local path = app.focused_node.absolute_path
  local is_ok, fallback = pcall(expand, path, app.explorer_config)
  local err = ""
  if not is_ok then
    err = tostring(fallback)
  elseif fallback then
    err = "# of nodes in this branch is more than fallback threshold: "
      .. tostring(state.fallback_threshold)
  end

  if err then
    return {
      { LogError = err },
    }
  end
end

local function close(app)
  if not app.focused_node or not is_dir(app.focused_node) then
    return
  end
  local path = app.focused_node.absolute_path
  state.tree[path].expansion = Expansion.CLOSED
  state.tree[app.pwd].all_expanded = false
end

local function toggle(app)
  if not app.focused_node or not is_dir(app.focused_node) then
    return
  end
  local path = app.focused_node.absolute_path
  if state.tree[path].expansion == Expansion.CLOSED then
    return open(app)
  elseif state.tree[path].expansion == Expansion.OPEN then
    return close(app)
  end
end

local function close_all(app)
  if not app.directory_buffer then
    return
  end
  for _, node in ipairs(app.directory_buffer.nodes) do
    if is_dir(node) then
      state.tree[node.absolute_path].expansion = Expansion.CLOSED
    end
  end
  state.tree[app.pwd].all_expanded = false
end

local function open_all(app)
  if not app.directory_buffer then
    return
  end
  for _, node in ipairs(app.directory_buffer.nodes) do
    if is_dir(node) then
      pcall(expand, node.absolute_path, app.explorer_config)
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

local function is_visibly_open(path)
  while true do
    if path == "/" then
      break
    end
    if state.tree[path] and state.tree[path].expansion ~= Expansion.OPEN then
      return false
    end
    path = xplr.util.dirname(path)
  end
  return true
end

local function has_visibly_max_depth(path)
  local branch = state.tree[path]
  if not branch or branch.expansion ~= Expansion.OPEN then
    return false
  end
  for _, node in ipairs(branch.nodes) do
    local child = state.tree[node.absolute_path]
    if child and child.expansion == Expansion.OPEN then
      return false
    end
  end
  return true
end

local function goto_next_open(app)
  if not state.is_layout_active and does_support_deep_branch_navigation then
    return {
      "NextVisitedDeepBranch",
    }
  end
  local skip = true
  local first = nil
  for _, line in ipairs(state.lines) do
    if line.path == app.pwd then
      skip = false
    elseif is_visibly_open(line.path) and has_visibly_max_depth(line.path) then
      if not skip then
        return {
          -- Set the history
          { FocusPath = line.path },
          "Enter",
        }
      elseif not first then
        first = line.path
      end
    end
  end

  if not xplr.config.general.enforce_bounded_index_navigation and first then
    return {
      -- Set the history
      { FocusPath = first },
      "Enter",
    }
  end
end

local function goto_prev_open(app)
  if not state.is_layout_active and does_support_deep_branch_navigation then
    return {
      "PreviousVisitedDeepBranch",
    }
  end

  local prev = nil
  for _, line in ipairs(state.lines) do
    if is_visibly_open(line.path) and has_visibly_max_depth(line.path) then
      if prev and line.path == app.pwd then
        return {
          -- Set the history
          { FocusPath = prev },
          "Enter",
        }
      else
        prev = line.path
      end
    end
  end

  if not xplr.config.general.enforce_bounded_index_navigation then
    return {
      -- Set the history
      { FocusPath = prev },
      "Enter",
    }
  end
end

local function focus_next(app)
  local dirbuf = app.directory_buffer
  if not dirbuf then
    return
  end

  local focused_path = app.focused_node and app.focused_node.absolute_path or app.pwd

  local first = nil
  local skip = true

  for _, line in ipairs(state.lines) do
    if line.path ~= state.root then
      if line.path == focused_path then
        skip = false
      elseif not skip then
        return {
          { FocusPath = line.path },
        }
      elseif not first then
        first = line.path
      end
    end
  end

  if first and not xplr.config.general.enforce_bounded_index_navigation then
    return {
      { FocusPath = first },
    }
  end
end

local function focus_prev(app)
  local dirbuf = app.directory_buffer
  if not dirbuf then
    return
  end

  local focused_path = app.focused_node and app.focused_node.absolute_path or app.pwd
  local prev = nil

  for _, line in ipairs(state.lines) do
    if line.path ~= state.root then
      if prev and line.path == focused_path then
        return {
          { FocusPath = prev },
        }
      else
        prev = line.path
      end
    end
  end

  if prev and not xplr.config.general.enforce_bounded_index_navigation then
    return {
      { FocusPath = prev },
    }
  end
end

xplr.fn.custom.tree_view = {
  render = render,
  toggle = toggle,
  toggle_all = toggle_all,
  toggle_layout = toggle_layout,
  open = open,
  close = close,
  open_all = open_all,
  close_all = close_all,
  goto_next_open = goto_next_open,
  goto_prev_open = goto_prev_open,
  focus_next = focus_next,
  focus_prev = focus_prev,
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
      state.is_layout_active = true
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

  args.focus_next_mode = args.focus_next_mode or "default"
  args.focus_next_key = args.focus_next_key or "]"

  args.focus_prev_mode = args.focus_prev_mode or "default"
  args.focus_prev_key = args.focus_prev_key or "["

  args.goto_next_open_mode = args.goto_next_open_mode or "default"
  args.goto_next_open_key = args.goto_next_open_key or ")"

  args.goto_prev_open_mode = args.goto_prev_open_mode or "default"
  args.goto_prev_open_key = args.goto_prev_open_key or "("

  args.close_all_and_back_mode = args.close_all_and_back_mode or "default"
  args.close_all_and_back_key = args.close_all_and_back_key or "backspace"

  state.indent = args.indent or state.indent

  state.fallback_layout = args.fallback_layout or state.fallback_layout
  state.fallback_threshold = args.fallback_threshold or state.fallback_threshold

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

  xplr.config.modes.builtin[args.focus_next_mode].key_bindings.on_key[args.focus_next_key] =
    {
      help = "next line",
      messages = {
        { CallLuaSilently = "custom.tree_view.focus_next" },
      },
    }

  xplr.config.modes.builtin[args.focus_prev_mode].key_bindings.on_key[args.focus_prev_key] =
    {
      help = "prev line",
      messages = {
        { CallLuaSilently = "custom.tree_view.focus_prev" },
      },
    }

  xplr.config.modes.builtin[args.goto_next_open_mode].key_bindings.on_key[args.goto_next_open_key] =
    {
      help = "goto next open",
      messages = {
        { CallLuaSilently = "custom.tree_view.goto_next_open" },
      },
    }

  xplr.config.modes.builtin[args.goto_prev_open_mode].key_bindings.on_key[args.goto_prev_open_key] =
    {
      help = "goto prev open",
      messages = {
        { CallLuaSilently = "custom.tree_view.goto_prev_open" },
      },
    }

  xplr.config.modes.builtin[args.close_all_and_back_mode].key_bindings.on_key[args.close_all_and_back_key] =
    {
      help = "close all and back and close",
      messages = {
        { CallLuaSilently = "custom.tree_view.close_all" },
        "Back",
        { CallLuaSilently = "custom.tree_view.close" },
      },
    }
end

return {
  setup = setup,
  render_node = render_node,
  is_visibly_open = is_visibly_open,
  has_visibly_max_depth = has_visibly_max_depth,
}
