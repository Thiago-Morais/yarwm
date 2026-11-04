-- Project-local Neovim settings for yarwm.
--
-- Loaded only if your own config enables it:
--     vim.o.exrc = true
-- The first time (and whenever this file changes) Neovim asks whether to
-- trust it — read it, then allow it, or run :trust.
--
-- Indentation, line endings etc. come from .editorconfig, which Neovim
-- reads natively; this file only adds what EditorConfig can't express.
-- Everything here applies to files inside this repo only.

local project_root = vim.fn.getcwd()

-- `:make check`, `:make lint`, `:make test` run the project's Makefile
-- targets in the dev container; errors (path:line:col: message) land in the
-- quickfix list, with paths relative to the repo root.
vim.o.makeprg = "make"

-- gopls runs on the host (editor tooling is not containerized), so these
-- settings just keep it consistent with the project's own checks.
-- vim.lsp.config needs Neovim 0.11+; older versions skip this.
if vim.lsp.config then
    vim.lsp.config("gopls", {
        settings = {
            gopls = {
                -- Plain gofmt, the same formatter `make fmt` and `make check` use.
                gofumpt = false,
                -- golangci-lint already runs staticcheck (`make lint`); don't
                -- report the same findings twice.
                staticcheck = false,
            },
        },
    })
end

-- Format Go files with gopls on save, matching `make fmt`, regardless of
-- your global format-on-save setup.
local project_group = vim.api.nvim_create_augroup("yarwm_project", { clear = true })
vim.api.nvim_create_autocmd("BufWritePre", {
    group = project_group,
    pattern = project_root .. "/*.go",
    callback = function(event)
        local gopls_clients = vim.lsp.get_clients({ bufnr = event.buf, name = "gopls" })
        if #gopls_clients > 0 then
            vim.lsp.buf.format({ bufnr = event.buf, name = "gopls", timeout_ms = 2000 })
        end
    end,
})
