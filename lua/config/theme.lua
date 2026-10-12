local M = {}

-- =========================================================
-- Configuration
-- =========================================================

local BG = '#161616'
local DEFAULT_THEME = 'tokyonight-night'

local STATE_DIR = vim.fn.stdpath 'state'
local THEME_STATE = STATE_DIR .. '/colorscheme'
local TRANSPARENCY_STATE = STATE_DIR .. '/transparency'

local TRANSPARENT_GROUPS = {
  -- Editor
  'Normal',
  'NormalNC',
  'EndOfBuffer',
  'SignColumn',
  'FoldColumn',
  'LineNr',
  'CursorLineNr',
  'StatusLine',
  'StatusLineNC',

  -- Floating windows
  'NormalFloat',
  'FloatBorder',
  'FloatTitle',
  'FloatFooter',

  -- Popup menu
  'Pmenu',
  'PmenuSel',
  'PmenuSbar',
  'PmenuThumb',

  -- Telescope
  'TelescopeNormal',
  'TelescopeBorder',
  'TelescopePromptNormal',
  'TelescopePromptBorder',
  'TelescopePromptTitle',
  'TelescopeResultsNormal',
  'TelescopeResultsBorder',
  'TelescopeResultsTitle',
  'TelescopePreviewNormal',
  'TelescopePreviewBorder',
  'TelescopePreviewTitle',

  -- nvim-cmp
  'CmpNormal',
  'CmpPmenu',
  'CmpSel',
  'CmpBorder',

  -- blink.cmp
  'BlinkCmpMenu',
  'BlinkCmpMenuBorder',
  'BlinkCmpDoc',
  'BlinkCmpDocBorder',
  'BlinkCmpSignatureHelp',
  'BlinkCmpSignatureHelpBorder',

  -- which-key
  'WhichKey',
  'WhichKeyNormal',
  'WhichKeyFloat',
  'WhichKeyGroup',
  'WhichKeyDesc',
  'WhichKeySeparator',
  'WhichKeyValue',
  'WhichKeyIcon',
  'WhichKeyBorder',
  'WhichKeyTitle',
  'WhichKeyCounter',
}

local state = {
  theme = DEFAULT_THEME,
  transparent = false,
  initialized = false,
}

-- =========================================================
-- Persistence
-- =========================================================

local function read_file(path)
  local file = io.open(path, 'r')
  if not file then return nil end

  local value = file:read '*a'
  file:close()

  return vim.trim(value)
end

local function write_file(path, value)
  local file, err = io.open(path, 'w')

  if not file then
    vim.notify(('Cannot save state: %s'):format(err or path), vim.log.levels.WARN)
    return false
  end

  file:write(tostring(value), '\n')
  file:close()

  return true
end

local function load_state()
  local theme = read_file(THEME_STATE)
  local transparent = read_file(TRANSPARENCY_STATE)

  state.theme = theme and theme ~= '' and theme or DEFAULT_THEME
  state.transparent = transparent == 'true'
  vim.g.transparent = state.transparent
end

-- =========================================================
-- Theme detection
-- =========================================================

local function is_tokyonight(name) return type(name) == 'string' and (name == 'tokyonight' or name:match '^tokyonight%-' ~= nil) end

local function is_gruvbox(name) return name == 'gruvbox' end

local function is_custom_theme(name) return is_tokyonight(name) or is_gruvbox(name) end

local function current_theme() return vim.g.colors_name or state.theme end

local function normalize_theme(name)
  if type(name) ~= 'string' or name == '' then return nil end

  return name
end

-- =========================================================
-- Terminal background
-- OSC 11 sets the terminal background.
-- OSC 111 resets it to the terminal default.
-- Only our two custom themes manage it.
-- =========================================================

local function osc(sequence)
  local stderr = vim.v.stderr

  if not stderr or stderr == 0 then return end

  pcall(vim.api.nvim_chan_send, stderr, '\027]' .. sequence .. '\027\\')
end

local function reset_terminal_background() osc '111' end

local function sync_terminal_background()
  if not is_custom_theme(current_theme()) or state.transparent then
    reset_terminal_background()
    return
  end

  local hl = vim.api.nvim_get_hl(0, {
    name = 'Normal',
    link = false,
  })

  if not hl.bg then
    reset_terminal_background()
    return
  end

  local r = bit.rshift(hl.bg, 16) % 256
  local g = bit.rshift(hl.bg, 8) % 256
  local b = hl.bg % 256

  osc(('11;rgb:%04x/%04x/%04x'):format(r * 257, g * 257, b * 257))
end

-- =========================================================
-- Theme setup
-- Configure only the selected custom theme.
-- =========================================================

local function setup_tokyonight()
  local ok, tokyonight = pcall(require, 'tokyonight')
  if not ok then return end

  local float_style = state.transparent and 'transparent' or 'dark'

  tokyonight.setup {
    transparent = state.transparent,

    styles = {
      comments = { italic = false },
      floats = float_style,
      sidebars = float_style,
    },

    on_colors = function(colors)
      colors.bg = BG
      colors.bg_dark = BG
      colors.bg_float = BG
      colors.bg_sidebar = BG
    end,

    on_highlights = function(hl, colors)
      local bg = state.transparent and 'NONE' or BG

      hl.Normal = { fg = colors.fg, bg = bg }
      hl.NormalNC = { fg = colors.fg, bg = bg }
      hl.NormalFloat = { fg = colors.fg, bg = bg }
      hl.FloatBorder = { fg = colors.blue, bg = bg }
      hl.FloatTitle = { fg = colors.cyan, bg = bg }

      hl.CmpBorder = { fg = colors.blue, bg = bg }
      hl.WhichKeyBorder = { fg = colors.blue, bg = bg }
      hl.WhichKeyTitle = { fg = colors.cyan, bg = bg }
    end,
  }
end

local function setup_gruvbox()
  local ok, gruvbox = pcall(require, 'gruvbox')
  if not ok then return end

  local bg = state.transparent and 'NONE' or BG
  local overrides = {}

  for _, group in ipairs(TRANSPARENT_GROUPS) do
    overrides[group] = { bg = bg }
  end

  gruvbox.setup {
    transparent_mode = state.transparent,

    italic = {
      comments = false,
    },

    contrast = '',

    palette_overrides = {
      dark0 = BG,
    },

    overrides = overrides,
  }
end

local function configure_custom_theme(theme)
  if is_tokyonight(theme) then
    setup_tokyonight()
  elseif is_gruvbox(theme) then
    setup_gruvbox()
  end
end

-- =========================================================
-- Highlight helpers
-- These must never run for third-party themes.
-- =========================================================

local function set_background(group, bg)
  local hl = vim.api.nvim_get_hl(0, {
    name = group,
    link = false,
  })

  hl.bg = bg
  hl.ctermbg = nil

  vim.api.nvim_set_hl(0, group, hl)
end

local function configure_window_border(theme)
  theme = theme or current_theme()

  vim.o.winborder = is_custom_theme(theme) and 'rounded' or 'none'
end

local function apply_transparency()
  if not state.transparent then return end

  for _, group in ipairs(TRANSPARENT_GROUPS) do
    set_background(group, nil)
  end
end

local function fix_custom_float_backgrounds()
  local bg = state.transparent and 'NONE' or BG

  -- Keep floating content and borders on the same background.
  -- Preserve each theme's foreground colors.
  for _, group in ipairs {
    'NormalFloat',
    'FloatBorder',
    'FloatTitle',
    'FloatFooter',

    'BlinkCmpMenu',
    'BlinkCmpMenuBorder',
    'BlinkCmpDoc',
    'BlinkCmpDocBorder',
    'BlinkCmpSignatureHelp',
    'BlinkCmpSignatureHelpBorder',

    'WhichKey',
    'WhichKeyNormal',
    'WhichKeyFloat',
    'WhichKeyBorder',
    'WhichKeyTitle',

    'CmpNormal',
    'CmpPmenu',
    'CmpBorder',

    'TelescopeNormal',
    'TelescopeBorder',
    'TelescopePromptNormal',
    'TelescopePromptBorder',
    'TelescopeResultsNormal',
    'TelescopeResultsBorder',
    'TelescopePreviewNormal',
    'TelescopePreviewBorder',
  } do
    local hl = vim.api.nvim_get_hl(0, {
      name = group,
      link = false,
    })

    hl.bg = bg
    vim.api.nvim_set_hl(0, group, hl)
  end
end

local function reset_plugin_highlights()
  -- Remove custom overrides so the active colorscheme
  -- can provide its own plugin highlight groups.
  for _, group in ipairs {
    'WhichKey',
    'WhichKeyNormal',
    'WhichKeyFloat',
    'WhichKeyGroup',
    'WhichKeyDesc',
    'WhichKeySeparator',
    'WhichKeyValue',
    'WhichKeyIcon',
    'WhichKeyBorder',
    'WhichKeyTitle',
    'WhichKeyCounter',

    'BlinkCmpMenu',
    'BlinkCmpMenuBorder',
    'BlinkCmpDoc',
    'BlinkCmpDocBorder',
    'BlinkCmpSignatureHelp',
    'BlinkCmpSignatureHelpBorder',
  } do
    pcall(vim.api.nvim_set_hl, 0, group, {})
  end
end

local function apply_custom_highlights()
  if not is_custom_theme(current_theme()) then return end

  if state.transparent then apply_transparency() end

  fix_custom_float_backgrounds()
end

-- =========================================================
-- Theme application
-- =========================================================
local function update_theme_flags(theme)
  vim.g.custom_theme_active = is_custom_theme(theme)
  vim.g.custom_theme_transparent = vim.g.custom_theme_active and state.transparent or false
end

function M.apply(theme)
  theme = normalize_theme(theme or state.theme)

  if not theme then
    vim.notify('Theme name cannot be empty.', vim.log.levels.WARN)
    return false
  end

  local custom = is_custom_theme(theme)

  -- Third-party themes always use their own opaque styling.
  if not custom then
    state.transparent = false
    vim.g.transparent = false
    write_file(TRANSPARENCY_STATE, false)
  end

  -- Configure only the requested custom theme.
  if custom then configure_custom_theme(theme) end

  local ok, err = pcall(vim.cmd.colorscheme, theme)

  if not ok then
    vim.notify(('Failed to load colorscheme "%s": %s'):format(theme, err), vim.log.levels.ERROR)
    return false
  end

  state.theme = theme
  write_file(THEME_STATE, theme)

  if custom then
    configure_window_border(theme)
    apply_custom_highlights()
    sync_terminal_background()
  else
    -- Do not change any highlight groups for other themes.
    reset_terminal_background()
  end

  update_theme_flags(theme)

  return true
end

-- =========================================================
-- Transparency
-- =========================================================

function M.toggle_transparency()
  local theme = current_theme()

  if not is_custom_theme(theme) then
    vim.notify('Transparency is supported only for Gruvbox and TokyoNight.', vim.log.levels.WARN)
    return
  end

  local previous = state.transparent
  state.transparent = not previous
  vim.g.transparent = state.transparent

  configure_custom_theme(theme)

  local ok, err = pcall(vim.cmd.colorscheme, theme)

  if not ok then
    state.transparent = previous
    vim.g.transparent = previous

    configure_custom_theme(theme)

    vim.notify(('Could not reload colorscheme: %s'):format(err), vim.log.levels.ERROR)
    return
  end

  write_file(TRANSPARENCY_STATE, state.transparent)

  apply_custom_highlights()
  sync_terminal_background()

  vim.notify(('Transparency: %s'):format(state.transparent and 'ON' or 'OFF'), vim.log.levels.INFO)
end

-- =========================================================
-- Status
-- =========================================================

function M.status() vim.notify(('Theme: %s\nTransparency: %s'):format(current_theme(), state.transparent and 'ON' or 'OFF'), vim.log.levels.INFO) end

-- =========================================================
-- Setup
-- =========================================================

function M.setup()
  if state.initialized then return end

  state.initialized = true
  load_state()
  update_theme_flags(state.theme)

  local group = vim.api.nvim_create_augroup('UserColorscheme', {
    clear = true,
  })

  vim.api.nvim_create_autocmd('ColorScheme', {
    group = group,

    callback = function()
      local theme = current_theme()
      state.theme = theme

      write_file(THEME_STATE, theme)
      update_theme_flags(theme)

      if not is_custom_theme(theme) then
        -- Never let our transparency setting leak into other themes.
        state.transparent = false
        vim.g.transparent = false
        write_file(TRANSPARENCY_STATE, false)
        reset_terminal_background()
        return
      end

      vim.schedule(function()
        -- Another colorscheme may have been loaded since scheduling.
        if current_theme() ~= theme then return end

        apply_custom_highlights()
        sync_terminal_background()
      end)
    end,
  })

  vim.api.nvim_create_autocmd({
    'VimResume',
    'UIEnter',
  }, {
    group = group,
    callback = function() vim.schedule(sync_terminal_background) end,
  })

  vim.api.nvim_create_autocmd({
    'VimLeave',
    'VimSuspend',
  }, {
    group = group,
    callback = reset_terminal_background,
  })

  vim.api.nvim_create_user_command('ToggleTransparency', M.toggle_transparency, { desc = 'Toggle custom theme transparency' })

  vim.api.nvim_create_user_command('ThemeStatus', M.status, { desc = 'Show colorscheme state' })

  vim.api.nvim_create_user_command('ThemeSet', function(opts) M.apply(opts.args) end, {
    nargs = 1,

    complete = function(_, _, _)
      local themes = {
        'gruvbox',
        'tokyonight-night',
        'tokyonight-storm',
        'tokyonight-moon',
        'tokyonight-day',
      }

      -- Include all installed colorschemes, including Slate.
      for _, name in ipairs(vim.fn.getcompletion('', 'color')) do
        if not vim.tbl_contains(themes, name) then table.insert(themes, name) end
      end

      return themes
    end,

    desc = 'Set colorscheme',
  })

  vim.keymap.set('n', '<leader>tt', M.toggle_transparency, {
    desc = 'Toggle custom theme transparency',
  })

  M.apply(state.theme)
end

return M
