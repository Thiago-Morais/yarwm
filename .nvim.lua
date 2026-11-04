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

-- Debugging with nvim-dap: `make debug-server` runs Delve inside the dev
-- container on 127.0.0.1:2345 (or $DEBUG_PORT, same variable as the
-- Makefile), and this adds a "yarwm: attach to make debug-server" entry to
-- nvim-dap's configuration picker (:DapContinue) that attaches to it.
--
-- Two details make this different from a normal nvim-dap-go setup:
--   * nvim-dap-go's "go" adapter always starts its own dlv on the host, so
--     attaching to the container's dlv needs a plain "server" adapter.
--   * The container sees the repo at /workspace; substitutePath maps it to
--     the repo's real path here, so breakpoints and stack frames line up.
--
-- Registered on the first Go buffer, so nvim-dap is only loaded when you
-- actually open Go code. Does nothing if nvim-dap isn't installed.
vim.api.nvim_create_autocmd("FileType", {
    group = project_group,
    pattern = "go",
    once = true,
    callback = function()
        local dap_available, dap = pcall(require, "dap")
        if not dap_available or not dap.providers then
            return
        end

        local debug_port = tonumber(vim.env.DEBUG_PORT) or 2345
        dap.adapters.yarwm_container_delve = {
            type = "server",
            host = "127.0.0.1",
            port = debug_port,
        }

        dap.providers.configs["yarwm"] = function(buffer_number)
            if vim.bo[buffer_number].filetype ~= "go" then
                return {}
            end
            return {
                {
                    name = "yarwm: attach to make debug-server",
                    type = "yarwm_container_delve",
                    request = "attach",
                    mode = "remote",
                    substitutePath = {
                        { from = project_root, to = "/workspace" },
                    },
                },
            }
        end
    end,
})
