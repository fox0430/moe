# Features

## Automatic backups

Automatic backups are enabled by default.

Automatic backups are recommended to keep it enabled
Backup to `~/.cache/moe/backups` by default.

You can set an interval to execute backups.

## QuickRun

QuickRun is like vim-quickrun.

You can use ```\ + r``` in normal mode. And ```run``` or ```Q``` command in Command mode.  
Currently QuickRun supports these languages by default and runs the following command internally.

- Nim ```nim c -r filename```
- C ```gcc filename && ./a.out```
- C++ ```g++ filename && ./a.out```
- bash ```bash filename```
- sh ```sh filename```

You can overwrite the command to be executed in the setting. That way you can use other compilers and languages.

## VSCode theme

moe supports VS Code themes in addition to dark, vivid, light, which are provided as standard.  
moe is searching and reflects the current VSCode theme if you already installed VSCode and you set "vscode" in the configuration file.

## Build on save

moe can build on save if you set true in BuildOnSave.enable in the configuration file.  
By default, the ```nim c filename``` command is executed.  
You can set workSpaceRoot and command to be executed in the configuration file.

## History mode (Backup file manager)

History mode is experimental feature.

You can check, restore and delete backup files in this mode.  
If you select backup file, you can check the difference from the current original file.  

## General-purpose autocomplete

moe can now use simple auto-complete.  
It is possible to auto-complete a words in the currently open buffer.

## Register

moe can use Vim-like registers.

### Number register
| Name | Description                                                                       |
|------|-----------------------------------------------------------------------------------|
| 0    | Yanked text                                                                       |
| 1    | Deleted line. One line or less is stored in the small delete register ```-```     |
| 2    | Every time a new delete command is issued, the contents of ```1``` are stored     |
| 3~9  | Similar to ```2```, the contents of the previous register are stored sequentially |

### Small delete register
| Name | Description   |
|------|---------------|
| -    | Deleted text  |

### Named register

| Name | Description            |
|------|------------------------|
| a~z  | Any text can be stored |

### No name register

Stores the value of the last used register.

## Runtime Key Mapping

moe supports Vim-like runtime key mapping commands. You can remap keys during an editing session using Command mode commands.

- `:nmap {lhs} {rhs}` - Map keys in Normal mode
- `:imap {lhs} {rhs}` - Map keys in Insert mode
- `:vmap {lhs} {rhs}` - Map keys in Visual modes
- `:rmap {lhs} {rhs}` - Map keys in Replace mode
- `:cmap {lhs} {rhs}` - Map keys in Command mode
- `:map {lhs} {rhs}` - Map keys in all modes (except Command mode)

All mappings are non-recursive (equivalent to Vim's `noremap`). `noremap`, `nnoremap`, `inoremap`, `vnoremap`, `cnoremap` are available as aliases.

Mappings are session-only and are not persisted across restarts. For persistent key mappings, use the `[KeyMapping]` section in `moerc.toml` or `keybindings.toml`. Use `[KeyMapping.All]` to apply mappings to all modes at once, `[KeyMapping.VisualAll]` for all visual modes, mode-specific sections like `[KeyMapping.Normal]`, `[KeyMapping.Visual]`, `[KeyMapping.VisualLine]`, `[KeyMapping.VisualBlock]` for individual modes, or special mode sections like `[KeyMapping.Filer]`, `[KeyMapping.BufferManager]`, `[KeyMapping.Terminal]`, etc. See [configfile.md](configfile.md#keymapping-table) and [configfile.md](configfile.md#keybindingstoml).

Key notation supports regular keys (`a`, `j`), modifier keys (`C-s`, `M-x`), special keys (`Escape`, `Enter`, `Tab`, `F1`-`F12`), and multi-key sequences in both space-separated (`j j`) and Vim-style concatenated (`jj`) notation.

See [How to use - Runtime Key Mapping](howtouse.md#runtime-key-mapping) for full details.

## EditorConfig

moe supports [EditorConfig](https://editorconfig.org) for maintaining consistent coding styles across editors.

When a file is opened, moe automatically looks for `.editorconfig` files and applies the settings to the buffer. EditorConfig is enabled by default and can be disabled in the configuration file.

Supported properties:

| Property | Description |
|---|---|
| `indent_style` | `space` or `tab` |
| `indent_size` | Number of columns for indentation |
| `tab_width` | Number of columns for tab character |
| `end_of_line` | `lf`, `crlf`, or `cr` |
| `charset` | `utf-8`, `utf-8-bom`, `utf-16be`, `utf-16le` |
| `trim_trailing_whitespace` | `true` or `false` (applied on save) |
| `insert_final_newline` | `true` or `false` |

Per-buffer overrides are automatically applied when switching between windows, so different files can have different settings simultaneously.

## Buffer Backends

moe supports multiple buffer backend implementations. Each backend offers different performance characteristics suited to different editing scenarios. You can configure the default backend in `moerc.toml`.

### Auto (Default)

Automatically selects the optimal backend based on file size. Files smaller than 10 MB use GapBuffer, and files 10 MB or larger use PieceTable.

### GapBuffer

A line-oriented gap buffer. Lines are stored in a flat array with a logical gap at the current edit position. Edits near the gap are very fast; edits far from the gap require moving the gap first.

Best for small to medium files with sequential/localized edits.

| Operation | Time Complexity |
|---|---|
| Get line | O(1) |
| Insert/Delete line | O(1) amortized |
| Insert into line | O(L) (L = line length) |
| Delete range | O(k) (k = lines spanned) |
| Undo/Redo | O(operation cost) |

### SqrtDecomp

A block list (sqrt decomposition). Lines are partitioned into blocks of up to 1024 lines. Blocks split when they grow too large and merge when they shrink too small, keeping block sizes balanced at roughly sqrt(n).

Best for large files with scattered (random-access) edit patterns.

| Operation | Time Complexity |
|---|---|
| Get line | O(sqrt(n)) |
| Insert/Delete line | O(sqrt(n)) |
| Insert into line | O(sqrt(n) + L) |
| Delete range | O(sqrt(n) * k) |
| Line count / Char count | O(1) (cached) |
| Undo/Redo | O(operation cost) |

### Rope

A B-tree rope where text is stored as raw bytes in leaf nodes. Internal nodes maintain subtree byte length and newline count metadata, enabling efficient tree walks. Tree height is O(log n) for all operations.

Best for large files with arbitrary-position edits requiring consistent O(log n) performance.

| Operation | Time Complexity |
|---|---|
| Get line | O(log n + L) |
| Insert/Delete line | O(log n) |
| Insert into line | O(log n + \|text\|) |
| Delete range | O(log n) |
| Find line start | O(log n) |
| Undo/Redo | O(operation cost) |

### PieceTable

A persistent Red-Black tree of "pieces", each describing a span in one of two append-only text buffers (original and add). The tree uses path-copying (Okasaki-style functional updates) so that old tree roots remain valid even after mutations. This enables **O(1) snapshot-based undo/redo**.

Best for any file size; particularly suited when undo/redo performance matters.

| Operation | Time Complexity |
|---|---|
| Get line | O(log P + L) |
| Insert/Delete line | O(log P) |
| Insert into line | O(log P) |
| Delete range | O(K log P) |
| Find line start | O(log P) |
| Take snapshot | **O(1)** |
| Restore snapshot (Undo/Redo) | **O(1)** |

(P = number of pieces in the tree. Coalescing keeps P bounded in practice.)

### Undo/Redo

- **GapBuffer, SqrtDecomp, Rope**: Operation-based undo/redo. Each edit records its inverse operation (e.g., insert ↔ delete). Undo replays the inverse; redo replays the original.
- **PieceTable**: Snapshot-based undo/redo. Before each edit, an O(1) snapshot of the tree root is captured. Undo/redo simply swaps the current root with the saved snapshot. Transactions (multi-operation edits) are also covered by a single snapshot.

### Comparison Summary

| Feature | GapBuffer | SqrtDecomp | Rope | PieceTable |
|---|---|---|---|---|
| Line access | **O(1)** | O(sqrt n) | O(log n) | O(log P) |
| Line insert/delete | O(1) amort | O(sqrt n) | O(log n) | O(log P) |
| Char count | O(n) | **O(1)** | **O(1)** | **O(1)** |
| Find line start | O(n) | O(n) | O(log n) | O(log P) |
| Undo/Redo | O(op) | O(op) | O(op) | **O(1)** |
| Structure | Mutable array | Mutable blocks | Mutable B-tree | Persistent RB-tree |
| Ideal file size | Small–Medium | Large | Large | Any |

## Terminal mode

moe has a built-in terminal emulator. You can run a shell or any command inside the editor window.

- `:terminal` - Open an interactive shell (default shell)
- `:terminal command` - Run a specific command (e.g. `:terminal ls -la`)

Terminal mode has two sub-modes:

- **Terminal-Input**: All keystrokes are forwarded to the running shell/command. Press `Ctrl-\ Ctrl-n` to switch to Terminal-Normal sub-mode.
- **Terminal-Normal**: Browse the terminal output. Press `i` or `a` to return to Terminal-Input sub-mode. Press `:` to enter command mode.

When a command finishes (e.g. `:terminal ls`), the output is displayed in a read-only scrollback view (Terminal-Normal sub-mode). When an interactive shell exits, the terminal window is automatically closed.
