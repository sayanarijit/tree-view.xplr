# tree-view.xplr

This plugin implements tree view support for xplr.

![demo](https://github.com/sayanarijit/tree-view.xplr/assets/11632726/b84da1aa-8b29-4398-a22a-f180006413ff)

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

    -- If you feel slowness, you might want to toggle back to the default view.
    toggle_layout_mode = "default",
    toggle_layout_key = "esc",


    -- Start xplr with tree view layout
    as_initial_layout = false,

    -- Disables toggling layout.
    as_default_layout = false,

    -- Automatically fallback to this layout for better performance if the
    -- branch contains # of nodes more than the threshold value
    fallback_layout = "Table",
    fallback_threshold = 500,  -- default: nil (disabled)

    -- Press backspace to close all and back
    close_all_and_back_mode = "default",
    close_all_and_back_key = "backspace",

    -- Toggle expansion without entering
    toggle_expansion_mode = "default",
    toggle_expansion_key = "o",

    -- Toggle expansion of all the nodes under pwd
    toggle_expansion_all_mode = "default",
    toggle_expansion_all_key = "O",

    -- Go to the next deepest level directory that's open
    goto_next_open_mode = "default",
    goto_next_open_key = ")",

    -- Go to the previous deepest level directory that's open
    goto_prev_open_mode = "default",
    goto_prev_open_key = "(",
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
