local project_root = vim.fn.getcwd()

-- vim.lsp.config needs Neovim 0.11+.
if vim.lsp.config then
    vim.lsp.config("gopls", {
        settings = {
            gopls = {
                -- `make fmt-check` uses plain gofmt.
                gofumpt = false,
                -- `make lint` already runs it; don't report findings twice.
                staticcheck = false,
            },
        },
    })
end

local project_group = vim.api.nvim_create_augroup("yarwm_project", { clear = true })

-- Same formatters as `make fmt`, whatever your global conform setup picks
-- (LazyVim's Go extra adds gofumpt, which `make fmt-check` would undo).
local project_formatters = {
    go = { "goimports", "gofmt", stop_after_first = true },
    markdown = { "prettierd", "prettier", stop_after_first = true },
    yaml = { "prettierd", "prettier", stop_after_first = true },
    json = { "prettierd", "prettier", stop_after_first = true },
}

local conform_available, conform = pcall(require, "conform")
if conform_available then
    for filetype, formatters in pairs(project_formatters) do
        conform.formatters_by_ft[filetype] = formatters
    end
end

vim.api.nvim_create_autocmd("BufWritePre", {
    group = project_group,
    pattern = project_root .. "/*",
    callback = function(event)
        if conform_available and project_formatters[vim.bo[event.buf].filetype] then
            conform.format({ bufnr = event.buf, timeout_ms = 2000 })
        elseif vim.bo[event.buf].filetype == "go" then
            local gopls_clients = vim.lsp.get_clients({ bufnr = event.buf, name = "gopls" })
            if #gopls_clients > 0 then
                vim.lsp.buf.format({ bufnr = event.buf, name = "gopls", timeout_ms = 2000 })
            end
        end
    end,
})

-- nvim-dap-go's "go" adapter always starts its own dlv on the host; attaching
-- to the container's dlv (`make debug-server`) needs a plain "server" adapter.
-- Registered on the first Go buffer so nvim-dap only loads for Go code.
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
                    -- The container sees the repo at /workspace.
                    substitutePath = {
                        { from = project_root, to = "/workspace" },
                    },
                },
            }
        end
    end,
})
