--[[
  Neovim Configuration

  Key concepts:
    Leader key = Space (the prefix for most custom bindings)
    Plugins managed by lazy.nvim (runs :Lazy to see plugin UI)
    LSP servers installed by Nix, not Mason (reproducible across machines)

  Getting started:
    :Tutor              Built-in tutorial (do this first!)
    <Space>sk           Search all keymaps (find any binding)
    <Space>sh           Search help tags
    <Space>sf           Search files
    <Space>sg           Search by grep across all files
    :checkhealth        Verify everything is working
--]]

-- Leader key must be set before lazy.nvim loads
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- =============================================================================
-- OPTIONS
-- =============================================================================

-- Line numbers
vim.opt.number = true
vim.opt.relativenumber = true -- Makes motion counts (5j, 12k) easy to see

-- Indentation (2 spaces, matching your nix style)
vim.opt.expandtab = true
vim.opt.shiftwidth = 2
vim.opt.tabstop = 2
vim.opt.smartindent = true

-- Search
vim.opt.ignorecase = true -- Case insensitive...
vim.opt.smartcase = true -- ...unless you type uppercase
vim.opt.hlsearch = true
vim.opt.incsearch = true

-- UI
vim.opt.termguicolors = true
vim.opt.signcolumn = "yes" -- Always show (prevents layout shift from LSP diagnostics)
vim.opt.cursorline = true
vim.opt.scrolloff = 8 -- Keep 8 lines visible above/below cursor
vim.opt.sidescrolloff = 8
vim.opt.wrap = false
vim.opt.showmode = false -- Lualine shows the mode instead
vim.opt.laststatus = 3 -- Single global statusline

-- Splits open in intuitive directions
vim.opt.splitbelow = true
vim.opt.splitright = true

-- Persistent undo (survives closing and reopening a file)
vim.opt.undofile = true
vim.opt.swapfile = false
vim.opt.backup = false

-- Performance
vim.opt.updatetime = 250
vim.opt.timeoutlen = 300 -- Faster which-key popup

-- Misc
vim.opt.mouse = "a" -- Mouse works everywhere (useful while learning)
vim.opt.clipboard = "unnamedplus" -- Yank/paste uses system clipboard
vim.opt.completeopt = { "menu", "menuone", "noselect" }
vim.opt.inccommand = "split" -- Live preview of :s substitutions

-- =============================================================================
-- KEYMAPS
-- =============================================================================

local map = vim.keymap.set

-- Clear search highlight
map("n", "<Esc>", "<cmd>nohlsearch<CR>")

-- Window navigation (Ctrl+hjkl instead of Ctrl+w then hjkl)
map("n", "<C-h>", "<C-w>h", { desc = "Move to left window" })
map("n", "<C-j>", "<C-w>j", { desc = "Move to below window" })
map("n", "<C-k>", "<C-w>k", { desc = "Move to above window" })
map("n", "<C-l>", "<C-w>l", { desc = "Move to right window" })

-- Resize windows
map("n", "<C-Up>", "<cmd>resize +2<CR>", { desc = "Increase window height" })
map("n", "<C-Down>", "<cmd>resize -2<CR>", { desc = "Decrease window height" })
map("n", "<C-Left>", "<cmd>vertical resize -2<CR>", { desc = "Decrease window width" })
map("n", "<C-Right>", "<cmd>vertical resize +2<CR>", { desc = "Increase window width" })

-- Move selected lines up/down in visual mode
map("v", "J", ":m '>+1<CR>gv=gv", { desc = "Move selection down" })
map("v", "K", ":m '<-2<CR>gv=gv", { desc = "Move selection up" })

-- Keep cursor centered when scrolling/searching
map("n", "<C-d>", "<C-d>zz")
map("n", "<C-u>", "<C-u>zz")
map("n", "n", "nzzzv")
map("n", "N", "Nzzzv")

-- Paste over selection without losing clipboard contents
map("x", "<leader>p", [["_dP]], { desc = "Paste without overwriting register" })

-- Quick save
map("n", "<leader>w", "<cmd>w<CR>", { desc = "Save file" })

-- Buffers
map("n", "<leader>bd", "<cmd>bdelete<CR>", { desc = "Delete buffer" })
map("n", "[b", "<cmd>bprevious<CR>", { desc = "Previous buffer" })
map("n", "]b", "<cmd>bnext<CR>", { desc = "Next buffer" })

-- Diagnostics
map("n", "[d", vim.diagnostic.goto_prev, { desc = "Previous diagnostic" })
map("n", "]d", vim.diagnostic.goto_next, { desc = "Next diagnostic" })
map("n", "<leader>e", vim.diagnostic.open_float, { desc = "Show diagnostic" })
map("n", "<leader>q", vim.diagnostic.setloclist, { desc = "Diagnostic list" })

-- =============================================================================
-- AUTOCOMMANDS
-- =============================================================================

-- Briefly highlight yanked text
vim.api.nvim_create_autocmd("TextYankPost", {
  group = vim.api.nvim_create_augroup("highlight-yank", { clear = true }),
  callback = function()
    (vim.hl or vim.highlight).on_yank()
  end,
})

-- Strip trailing whitespace on save
vim.api.nvim_create_autocmd("BufWritePre", {
  group = vim.api.nvim_create_augroup("trim-whitespace", { clear = true }),
  pattern = "*",
  callback = function()
    local save = vim.fn.winsaveview()
    vim.cmd([[%s/\s\+$//e]])
    vim.fn.winrestview(save)
  end,
})

-- Go uses tabs, not spaces
vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("go-indent", { clear = true }),
  pattern = "go",
  callback = function()
    vim.opt_local.expandtab = false
    vim.opt_local.shiftwidth = 4
    vim.opt_local.tabstop = 4
  end,
})

-- Python uses 4-space indent
vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("python-indent", { clear = true }),
  pattern = "python",
  callback = function()
    vim.opt_local.shiftwidth = 4
    vim.opt_local.tabstop = 4
  end,
})

-- Return to last edit position when reopening a file
vim.api.nvim_create_autocmd("BufReadPost", {
  group = vim.api.nvim_create_augroup("restore-cursor", { clear = true }),
  callback = function(args)
    local mark = vim.api.nvim_buf_get_mark(args.buf, '"')
    local line_count = vim.api.nvim_buf_line_count(args.buf)
    if mark[1] > 0 and mark[1] <= line_count then
      pcall(vim.api.nvim_win_set_cursor, 0, mark)
    end
  end,
})

-- =============================================================================
-- LAZY.NVIM (Plugin Manager) - Bootstrap
-- =============================================================================

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- =============================================================================
-- PLUGINS
-- =============================================================================

require("lazy").setup({

  -- ---------------------------------------------------------------------------
  -- Theme: Tokyo Night (matches your terminal/sketchybar Tokyo Dark palette)
  -- ---------------------------------------------------------------------------
  {
    "folke/tokyonight.nvim",
    lazy = false,
    priority = 1000, -- Load before everything else
    opts = {
      style = "night", -- Darkest variant
      transparent = true, -- Let terminal's background/blur show through
      terminal_colors = true,
      styles = {
        comments = { italic = true },
        keywords = { italic = true },
        sidebars = "transparent",
        floats = "transparent",
      },
    },
    config = function(_, opts)
      require("tokyonight").setup(opts)
      vim.cmd.colorscheme("tokyonight")
    end,
  },

  -- ---------------------------------------------------------------------------
  -- UI
  -- ---------------------------------------------------------------------------

  -- Status line (replaces the default one)
  {
    "nvim-lualine/lualine.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = {
      options = {
        theme = "tokyonight",
        globalstatus = true,
        component_separators = { left = "", right = "" },
        section_separators = { left = "", right = "" },
      },
      sections = {
        lualine_a = { "mode" },
        lualine_b = { "branch", "diff", "diagnostics" },
        lualine_c = { { "filename", path = 1 } }, -- Show relative path
        lualine_x = { "filetype" },
        lualine_y = { "progress" },
        lualine_z = { "location" },
      },
    },
  },

  -- Keybinding hints: press Space and wait to see what's available
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {
      spec = {
        { "<leader>b", group = "buffer" },
        { "<leader>c", group = "code" },
        { "<leader>g", group = "git" },
        { "<leader>s", group = "search" },
      },
    },
  },

  -- Indent guides (subtle vertical lines showing indentation level)
  {
    "lukas-reineke/indent-blankline.nvim",
    main = "ibl",
    event = { "BufReadPost", "BufNewFile" },
    opts = {
      indent = { char = "│" },
      scope = { enabled = true },
    },
  },

  -- Highlight TODO/FIXME/HACK/NOTE comments
  {
    "folke/todo-comments.nvim",
    event = { "BufReadPost", "BufNewFile" },
    dependencies = { "nvim-lua/plenary.nvim" },
    opts = {},
  },

  -- ---------------------------------------------------------------------------
  -- Navigation
  -- ---------------------------------------------------------------------------

  -- Fuzzy finder (powered by your existing ripgrep + fd)
  {
    "nvim-telescope/telescope.nvim",
    event = "VimEnter",
    branch = "0.1.x",
    dependencies = {
      "nvim-lua/plenary.nvim",
      { "nvim-telescope/telescope-fzf-native.nvim", build = "make" },
      "nvim-telescope/telescope-ui-select.nvim",
      "nvim-tree/nvim-web-devicons",
    },
    config = function()
      local telescope = require("telescope")
      telescope.setup({
        defaults = {
          file_ignore_patterns = { "node_modules", ".git/", "result" },
        },
        extensions = {
          ["ui-select"] = {
            require("telescope.themes").get_dropdown(),
          },
        },
      })
      pcall(telescope.load_extension, "fzf")
      pcall(telescope.load_extension, "ui-select")

      local builtin = require("telescope.builtin")
      map("n", "<leader>sf", builtin.find_files, { desc = "Search files" })
      map("n", "<leader>sg", builtin.live_grep, { desc = "Search by grep" })
      map("n", "<leader>sw", builtin.grep_string, { desc = "Search current word" })
      map("n", "<leader>sh", builtin.help_tags, { desc = "Search help" })
      map("n", "<leader>sk", builtin.keymaps, { desc = "Search keymaps" })
      map("n", "<leader>sd", builtin.diagnostics, { desc = "Search diagnostics" })
      map("n", "<leader>sr", builtin.resume, { desc = "Resume last search" })
      map("n", "<leader>s.", builtin.oldfiles, { desc = "Search recent files" })
      map("n", "<leader><leader>", builtin.buffers, { desc = "Find open buffers" })
      map("n", "<leader>/", function()
        builtin.current_buffer_fuzzy_find(require("telescope.themes").get_dropdown({
          winblend = 10,
          previewer = false,
        }))
      end, { desc = "Fuzzy search in buffer" })
    end,
  },

  -- File explorer: press - to browse parent directory (edit dirs like buffers)
  {
    "stevearc/oil.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      require("oil").setup({
        view_options = { show_hidden = true },
      })
      map("n", "-", "<cmd>Oil<CR>", { desc = "Open parent directory" })
    end,
  },

  -- Quick jump: press s then type 2 chars to jump anywhere visible
  {
    "folke/flash.nvim",
    event = "VeryLazy",
    opts = {},
    keys = {
      { "s", mode = { "n", "x", "o" }, function() require("flash").jump() end, desc = "Flash jump" },
      { "S", mode = { "n", "x", "o" }, function() require("flash").treesitter() end, desc = "Flash treesitter" },
    },
  },

  -- ---------------------------------------------------------------------------
  -- Editing
  -- ---------------------------------------------------------------------------

  -- Syntax highlighting + text objects via Treesitter
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    event = { "BufReadPost", "BufNewFile" },
    dependencies = { "nvim-treesitter/nvim-treesitter-textobjects" },
    config = function()
      require("nvim-treesitter.configs").setup({
        ensure_installed = {
          -- Your languages
          "go", "gomod", "gosum",
          "python",
          "typescript", "tsx", "javascript",
          "svelte",
          "html", "css", "scss",
          "nix",
          "lua",
          "bash",
          "sql",
          "prisma",
          -- Config / data
          "json", "jsonc", "yaml", "toml",
          "dockerfile",
          "markdown", "markdown_inline",
          "helm",
          -- Vim / general
          "vim", "vimdoc", "query",
          "regex", "diff", "gitcommit", "git_rebase",
        },
        auto_install = true,
        highlight = { enable = true },
        indent = { enable = true },
        -- Treesitter text objects: select/move by function, class, argument
        -- Example: daf = delete around function, vif = select inside function
        textobjects = {
          select = {
            enable = true,
            lookahead = true,
            keymaps = {
              ["af"] = { query = "@function.outer", desc = "around function" },
              ["if"] = { query = "@function.inner", desc = "inside function" },
              ["ac"] = { query = "@class.outer", desc = "around class" },
              ["ic"] = { query = "@class.inner", desc = "inside class" },
              ["aa"] = { query = "@parameter.outer", desc = "around argument" },
              ["ia"] = { query = "@parameter.inner", desc = "inside argument" },
            },
          },
          move = {
            enable = true,
            goto_next_start = {
              ["]f"] = "@function.outer",
              ["]c"] = "@class.outer",
              ["]a"] = "@parameter.inner",
            },
            goto_previous_start = {
              ["[f"] = "@function.outer",
              ["[c"] = "@class.outer",
              ["[a"] = "@parameter.inner",
            },
          },
        },
      })
    end,
  },

  -- Surround operations: cs"' (change surrounding " to '), ysiw) (wrap word in parens)
  {
    "kylechui/nvim-surround",
    version = "*",
    event = "VeryLazy",
    opts = {},
  },

  -- Auto-close brackets and quotes
  {
    "windwp/nvim-autopairs",
    event = "InsertEnter",
    opts = {},
  },

  -- ---------------------------------------------------------------------------
  -- LSP (Language Server Protocol) - Intellisense, go-to-definition, etc.
  -- ---------------------------------------------------------------------------
  {
    "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = { "hrsh7th/cmp-nvim-lsp" },
    config = function()
      local lspconfig = require("lspconfig")
      local capabilities = require("cmp_nvim_lsp").default_capabilities()

      -- Keymaps activate only when an LSP server attaches to a buffer
      vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup("lsp-attach", { clear = true }),
        callback = function(event)
          local buf = event.buf
          local o = function(desc) return { buffer = buf, desc = desc } end

          -- Navigation
          map("n", "gd", require("telescope.builtin").lsp_definitions, o("Go to definition"))
          map("n", "gr", require("telescope.builtin").lsp_references, o("Go to references"))
          map("n", "gI", require("telescope.builtin").lsp_implementations, o("Go to implementation"))
          map("n", "gy", require("telescope.builtin").lsp_type_definitions, o("Go to type definition"))
          map("n", "gD", vim.lsp.buf.declaration, o("Go to declaration"))

          -- Code actions
          map("n", "<leader>cr", vim.lsp.buf.rename, o("Rename symbol"))
          map("n", "<leader>ca", vim.lsp.buf.code_action, o("Code action"))
          map("n", "<leader>cs", require("telescope.builtin").lsp_document_symbols, o("Document symbols"))
          map("n", "<leader>cS", require("telescope.builtin").lsp_dynamic_workspace_symbols, o("Workspace symbols"))

          -- Hover docs (K is the default, but being explicit)
          map("n", "K", vim.lsp.buf.hover, o("Hover documentation"))

          -- Highlight references of symbol under cursor
          local client = vim.lsp.get_client_by_id(event.data.client_id)
          if client and client.supports_method("textDocument/documentHighlight") then
            local hl_group = vim.api.nvim_create_augroup("lsp-highlight", { clear = false })
            vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
              buffer = buf,
              group = hl_group,
              callback = vim.lsp.buf.document_highlight,
            })
            vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
              buffer = buf,
              group = hl_group,
              callback = vim.lsp.buf.clear_references,
            })
          end
        end,
      })

      -- Server configs (all binaries installed via Nix, available on PATH)

      lspconfig.nil_ls.setup({
        capabilities = capabilities,
        settings = {
          ["nil"] = {
            formatting = { command = { "nixfmt" } },
            nix = { flake = { autoArchive = true } },
          },
        },
      })

      lspconfig.gopls.setup({
        capabilities = capabilities,
        settings = {
          gopls = {
            analyses = { unusedparams = true, shadow = true },
            staticcheck = true,
            gofumpt = true,
          },
        },
      })

      lspconfig.pyright.setup({ capabilities = capabilities })

      lspconfig.ts_ls.setup({ capabilities = capabilities })

      lspconfig.svelte.setup({ capabilities = capabilities })

      lspconfig.lua_ls.setup({
        capabilities = capabilities,
        settings = {
          Lua = {
            runtime = { version = "LuaJIT" },
            workspace = { checkThirdParty = false, library = { vim.env.VIMRUNTIME } },
            diagnostics = { globals = { "vim" } },
            telemetry = { enable = false },
          },
        },
      })

      lspconfig.yamlls.setup({
        capabilities = capabilities,
        settings = {
          yaml = {
            schemas = {
              ["https://json.schemastore.org/github-workflow.json"] = "/.github/workflows/*",
              ["https://raw.githubusercontent.com/compose-spec/compose-spec/master/schema/compose-spec.json"] = "docker-compose*.yml",
            },
          },
        },
      })

      lspconfig.jsonls.setup({
        capabilities = capabilities,
        settings = { json = { validate = { enable = true } } },
      })

      lspconfig.html.setup({ capabilities = capabilities })
      lspconfig.cssls.setup({ capabilities = capabilities })
      lspconfig.eslint.setup({ capabilities = capabilities })
      lspconfig.tailwindcss.setup({ capabilities = capabilities })
      lspconfig.bashls.setup({ capabilities = capabilities })
      lspconfig.dockerls.setup({ capabilities = capabilities })
      lspconfig.helm_ls.setup({ capabilities = capabilities })
      lspconfig.marksman.setup({ capabilities = capabilities })
      lspconfig.taplo.setup({ capabilities = capabilities })
    end,
  },

  -- ---------------------------------------------------------------------------
  -- Completion
  -- ---------------------------------------------------------------------------
  {
    "hrsh7th/nvim-cmp",
    event = "InsertEnter",
    dependencies = {
      "hrsh7th/cmp-nvim-lsp", -- LSP completions
      "hrsh7th/cmp-buffer", -- Words from current buffer
      "hrsh7th/cmp-path", -- File paths
      "saadparwaiz1/cmp_luasnip", -- Snippet completions
      {
        "L3MON4D3/LuaSnip",
        version = "v2.*",
        dependencies = { "rafamadriz/friendly-snippets" },
        config = function()
          require("luasnip.loaders.from_vscode").lazy_load()
        end,
      },
    },
    config = function()
      local cmp = require("cmp")
      local luasnip = require("luasnip")

      cmp.setup({
        snippet = {
          expand = function(args)
            luasnip.lsp_expand(args.body)
          end,
        },
        completion = { completeopt = "menu,menuone,noinsert" },
        -- Ctrl+n/p to navigate, Ctrl+y to confirm, Tab to jump through snippets
        mapping = cmp.mapping.preset.insert({
          ["<C-n>"] = cmp.mapping.select_next_item(),
          ["<C-p>"] = cmp.mapping.select_prev_item(),
          ["<C-b>"] = cmp.mapping.scroll_docs(-4),
          ["<C-f>"] = cmp.mapping.scroll_docs(4),
          ["<C-y>"] = cmp.mapping.confirm({ select = true }),
          ["<C-Space>"] = cmp.mapping.complete(),
          ["<Tab>"] = cmp.mapping(function(fallback)
            if luasnip.expand_or_locally_jumpable() then
              luasnip.expand_or_jump()
            else
              fallback()
            end
          end, { "i", "s" }),
          ["<S-Tab>"] = cmp.mapping(function(fallback)
            if luasnip.locally_jumpable(-1) then
              luasnip.jump(-1)
            else
              fallback()
            end
          end, { "i", "s" }),
        }),
        sources = {
          { name = "nvim_lsp" },
          { name = "luasnip" },
          { name = "buffer" },
          { name = "path" },
        },
      })
    end,
  },

  -- ---------------------------------------------------------------------------
  -- Formatting (auto-format on save)
  -- ---------------------------------------------------------------------------
  {
    "stevearc/conform.nvim",
    event = "BufWritePre",
    cmd = "ConformInfo",
    config = function()
      require("conform").setup({
        formatters_by_ft = {
          nix = { "nixfmt" },
          lua = { "stylua" },
          go = { "gofumpt" },
          python = { "black" },
          javascript = { "prettierd", "prettier", stop_after_first = true },
          typescript = { "prettierd", "prettier", stop_after_first = true },
          typescriptreact = { "prettierd", "prettier", stop_after_first = true },
          javascriptreact = { "prettierd", "prettier", stop_after_first = true },
          svelte = { "prettierd", "prettier", stop_after_first = true },
          html = { "prettierd", "prettier", stop_after_first = true },
          css = { "prettierd", "prettier", stop_after_first = true },
          json = { "prettierd", "prettier", stop_after_first = true },
          yaml = { "prettierd", "prettier", stop_after_first = true },
          markdown = { "prettierd", "prettier", stop_after_first = true },
          sh = { "shfmt" },
          bash = { "shfmt" },
        },
        format_on_save = {
          timeout_ms = 500,
          lsp_format = "fallback",
        },
      })
      map("n", "<leader>cf", function()
        require("conform").format({ async = true, lsp_format = "fallback" })
      end, { desc = "Format buffer" })
    end,
  },

  -- ---------------------------------------------------------------------------
  -- Git
  -- ---------------------------------------------------------------------------

  -- Signs in the gutter + hunk operations
  {
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPost", "BufNewFile" },
    opts = {
      signs = {
        add = { text = "▎" },
        change = { text = "▎" },
        delete = { text = "" },
        topdelete = { text = "" },
        changedelete = { text = "▎" },
      },
      on_attach = function(bufnr)
        local gs = require("gitsigns")
        local o = function(desc) return { buffer = bufnr, desc = desc } end

        map("n", "]h", gs.next_hunk, o("Next git hunk"))
        map("n", "[h", gs.prev_hunk, o("Previous git hunk"))
        map("n", "<leader>gs", gs.stage_hunk, o("Stage hunk"))
        map("n", "<leader>gr", gs.reset_hunk, o("Reset hunk"))
        map("n", "<leader>gS", gs.stage_buffer, o("Stage entire buffer"))
        map("n", "<leader>gu", gs.undo_stage_hunk, o("Undo stage hunk"))
        map("n", "<leader>gp", gs.preview_hunk, o("Preview hunk"))
        map("n", "<leader>gb", function() gs.blame_line({ full = true }) end, o("Blame line"))
      end,
    },
  },

  -- Full git UI (:Git blame, :Git diff, :Git log)
  { "tpope/vim-fugitive", cmd = "Git" },

}, {
  -- lazy.nvim settings
  install = { colorscheme = { "tokyonight" } },
  checker = { enabled = false }, -- Don't auto-check for updates (nix handles reproducibility)
  performance = {
    rtp = {
      disabled_plugins = {
        "gzip",
        "netrwPlugin", -- Replaced by oil.nvim
        "tarPlugin",
        "tohtml",
        "zipPlugin",
      },
    },
  },
})
