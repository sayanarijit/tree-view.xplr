# tree-view.xplr

This plugin implements tree view support for xplr.

[![demo](https://s12.gifyu.com/images/SQGR3.gif)](https://gifyu.com/image/SQGR3)

## Requirements

None

## Installation

### Install manually

- Add the following line in `~/.config/xplr/init.lua`

  ```lua
  local home = os.getenv("HOME")
  package.path = home
    .. "/.config/xplr/plugins/?/src/init.lua;"
    .. home
    .. "/.config/xplr/plugins/?.lua;"
    .. package.path
  ```

- Clone the plugin

```bash
mkdir -p ~/.config/xplr/plugins
git clone https://github.com/sayanarijit/tree-view.xplr ~/.config/xplr/plugins/tree-view
```

- Require the module in `~/.config/xplr/init.lua`

```lua
require("tree-view").setup()

-- or

require("tree-view").setup({
    mode = "switch_layout",
    key = "T",

    fullscreen = false,

    indent = "  ",

    toggle_layout_mode = "default",
    toggle_layout_key = "esc",

    toggle_expansion_mode = "default",
    toggle_expansion_key = "o",

    toggle_expansion_all_mode = "default",
    toggle_expansion_all_key = "O",

    as_default_layout = false,
    as_initial_layout = false,
})

-- In default mode:
--   Press `esc` to toggle layout.
--   Press `o` to toggle expansion.
--   Press `O` to toggle all expansion.
-- In switch_layout mode:
--   Press `T` to switch to tree layout
```

## Also see:

- [zentable.xplr](https://github.com/sayanarijit/zentable.xplr)
- [dual-pane.xplr](https://github.com/sayanarijit/dual-pane.xplr)
- [tri-pane.xplr](https://github.com/sayanarijit/tri-pane.xplr)
