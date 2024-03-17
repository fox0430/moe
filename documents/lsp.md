# Language Server Protocol

Moe supports [LSP](https://microsoft.github.io/language-server-protocol/) but work in progress and not recommended for use yet.

Currently, I tested [Nim language server](https://github.com/nim-lang/langserver) and [rust-analyzer](https://rust-analyzer.github.io).

Please feedback, bug reports and PRs.

## Supported LSP commands

- `Initialize`
- `shutdown`
- `window/showMessage`
- `window/logMessage`
- `window/workDoneProgress/create`
- `workspace/configuration`
- `workspace/didChangeConfiguration`
- `textDocument/publishDiagnostics`
- `textDocument/didOpen`
- `textDocument/didChange`
- `textDocument/didSave`
- `textDocument/didClose`
- `textDocument/hover`
- `$/progress`

## Configuration

Please edit you configuration file.

Example
```toml
[Lsp]
enable = true

[Lsp.nim]
# File extensions
extensions = ["nim"]

# The LSP server command
command = "nimlangserver"

# The level of verbosity 
trace = "verbose"
```

Configure each language by adding table `[Lsp.{languageId}]`.
If you want to add rust-analyzer,
```toml
[Lsp]
enable = true

[Lsp.nim]
extensions = ["nim"]
command = "nimlangserver"
trace = "off"

[Lsp.rust]
extensions = ["rs"]
command = "rust-analyzer"
trace = "messages"
```

## Uses

### Hover

Press `K` on the word in Normal mode.

![hover](https://github.com/fox0430/moe/assets/15966436/9e1f78d7-c52d-4bf7-bb51-7d86659ffeb5)

### Diagnostics

Results will be received from the LPS server and displayed automatically.

![diagnostics](https://github.com/fox0430/moe/assets/15966436/3cc99b32-c53a-4878-846d-8fd44b4a6fb2)

### Completion

The completion is still under development but available.

![moe-completion](https://github.com/fox0430/moe/assets/15966436/c1788c00-45f9-4c45-b80f-ebe00638d91d)
