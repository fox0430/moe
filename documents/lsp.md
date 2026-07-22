# Language Server Protocol

Moe supports [LSP](https://microsoft.github.io/language-server-protocol/) but work in progress and not recommended for use yet.

Currently, I tested [Nim language server](https://github.com/nim-lang/langserver) and [rust-analyzer](https://rust-analyzer.github.io).

Please feedback, bug reports and PRs.

## Supported LSP commands

- `Initialize`
- `shutdown`
- `exit`
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
- `textDocument/completion`
- `textDocument/semanticTokens/full`
- `workspace/semanticTokens/refresh`
- `textDocument/inlayHint`
- `workspace/inlayHint/refresh`
- `textDocument/declaration`
- `textDocument/definition`
- `textDocument/typeDefinition`
- `textDocument/implementation`
- `textDocument/references`
- `textDocument/rename`
- `textDocument/prepareCallHierarchy`
- `callHierarchy/incomingCalls`
- `callHierarchy/outgoingCalls`
- `textDocument/documentHighlight`
- `textDocument/documentLink`
- `documentLink/resolve`
- `textDocument/codeLens`
- `workspace/codeLens/refresh`
- `codeLens/resolve`
- `workspace/executeCommand`
- `$/progress`
- `$/cancelRequest`
- `textDocument/foldingRange`
- `textDocument/selectionRange`
- `textDocument/documentSymbol`
- `textDocument/signatureHelp`
- `textDocument/formatting`

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

## Features

### Hover

Press `K` on the word in Normal mode.

![hover](https://github.com/fox0430/moe/assets/15966436/9e1f78d7-c52d-4bf7-bb51-7d86659ffeb5)

### Diagnostics

Results will be received from the LSP server and displayed automatically.

![diagnostics](https://github.com/fox0430/moe/assets/15966436/3cc99b32-c53a-4878-846d-8fd44b4a6fb2)

#### Auto Hover

When `Lsp.Diagnostics.autoHover` is enabled (default: `true`), diagnostic messages are automatically shown in a hover popup when the cursor moves onto a diagnostic range. The popup is dismissed when the cursor moves off the diagnostic.

You can also press `K` to manually show hover information, which will include both diagnostic messages and LSP hover content if available.

The delay before the auto hover popup appears can be configured with `Lsp.Diagnostics.autoHoverDelay` (default: `300` ms).

```toml
[Lsp.Diagnostics]
enable = true
autoHover = true
autoHoverDelay = 300
```

### Signature Help

`Ctrl-r` in Normal mode. Show the signature help on the hover.

![moe-signature](https://github.com/user-attachments/assets/7c8f2487-7cd9-4bb5-8833-2e495fdd21b3)

### Document Formatting

`lspformat` in Command mode. Format the buffer.

### Folding Range

`lspfold` in Command mode. Requests folding ranges from the language server and
collapses them all (fold-all), including nested ranges such as a class, its
methods, and their inner blocks. Open them again with `zo`/`zR`. Manual folds
created with `zf` are preserved when running `lspfold`. The command does nothing
if folding range is disabled in the config or unsupported by the server.

> [!NOTE]
> Editing a line inside a collapsed fold (delete, change, paste, insert, a
> visual-mode edit, etc.) first reveals the fold and then edits only the
> targeted line or range. Unlike Vim, moe does not operate on a closed fold as a
> single unit (e.g. `dd` on a closed fold deletes one line, not the whole fold),
> so hidden text is never changed without being shown first. Pure yanks leave
> the fold closed. This applies to both LSP and manual (`zf`) folds.

![moe](https://github.com/user-attachments/assets/9fac0f03-fa70-49f8-9da0-ea9ae0c0ce04)

### Selection Range

`Ctrl-s` in Normal mode. Enter Visual mode and you can repeat it.

### Document Symbol

`Space-o` in Normal mode. You can select a symbol in the list and you can jump.

![moe-symbol](https://github.com/user-attachments/assets/67f15598-1e66-4c83-a99b-b0f1b21ef2b9)

### Completion

The completion is still under development but available.

![moe-completion](https://github.com/fox0430/moe/assets/15966436/c1788c00-45f9-4c45-b80f-ebe00638d91d)

### Semantic Tokens

Syntax highlighting with Semantic Tokens. Currently, only full is supported.

![moe-semantictokens](https://github.com/fox0430/moe/assets/15966436/234ed9d2-7251-4e5c-a242-626b45e091e7)

### Inlay Hint

Display types at the end of lines with LSP InlayHint.

![moe-inlayhint](https://github.com/fox0430/moe/assets/15966436/6e096bf4-0561-457d-944f-2526177fe33a)

### Inline Value

This is experimental feature. Not tested.

### Goto Declaration

`gc` command in Normal mode. If the file is not currently, it will open in a new window.

### Goto Definition

`gd` command in Normal mode. If the file is not currently, it will open in a new window.

### Goto TypeDefinition

`gy` command in Normal mode. If the file is not currently, it will open in a new window.

### Goto Implementation

`gi` command in Normal mode. If the file is not currently, it will open in a new window.

### Find References

`gr` command in Normal mode. Open References mode.

![moe-references](https://github.com/fox0430/moe/assets/15966436/fe34a5f9-a68b-4300-ad82-7c8bd7150d01)

### Call Hierarchy

`gh` command in Noemal mode. Open Call Hierarchy viewer

![moe-call](https://github.com/fox0430/moe/assets/15966436/0c2bbf9d-f068-4e8c-bdf6-1cf4c3f02a9d)

### Document Highlight

If this feature is enabled, Highlight.currentWord will be forced to disable.

![moe-documenthighlight](https://github.com/fox0430/moe/assets/15966436/371b38e1-3d03-4773-847f-02ade38e6eb7)

### Document Link

`gl` command in Normal mode. Jump to a target.

### Code Lens

Currently, Only supported in rust-analyzer.

Please set true to `Lps.CodeLens.enable`, `Lsp.rust.rustAnalyzerRunSingle`, `Lsp.rust.rustAnalyzerDebugSingle`.

`\c` command in Normal mode on A code lens line.

![moe-codelens](https://github.com/user-attachments/assets/6c178bb1-578a-44f0-8beb-1c0bfbd7bed1)

### Rename

`Space-r` command in Normal mode. Enter a new name in the command line.

![moe-rename](https://github.com/fox0430/moe/assets/15966436/420ea178-c9fe-4053-8410-849fb845c698)

### Execute Command

Work in prgoress
