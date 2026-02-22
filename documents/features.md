# Features

## Automatic backups

Automatic backups are enabled by default.

Automatic backups are recommended to keep it enabled
Backup to `~/.cache/moe/backups` by default.

You can set an interval to execute backups.

## QuickRun

QuickRun is like vim-quickrun.

You can use ```\ + r``` in normal mode. And ```run``` or ```Q``` command in ex mode.  
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

moe supports Vim-like runtime key mapping commands. You can remap keys during an editing session using Ex mode commands.

- `:nmap {lhs} {rhs}` - Map keys in Normal mode
- `:imap {lhs} {rhs}` - Map keys in Insert mode
- `:vmap {lhs} {rhs}` - Map keys in Visual modes
- `:rmap {lhs} {rhs}` - Map keys in Replace mode
- `:cmap {lhs} {rhs}` - Map keys in Command-line mode
- `:map {lhs} {rhs}` - Map keys in all modes

All mappings are non-recursive (equivalent to Vim's `noremap`). `noremap`, `nnoremap`, `inoremap`, `vnoremap`, `cnoremap` are available as aliases.

Mappings are session-only and are not persisted across restarts. For persistent key mappings, use the `[KeyMapping]` section in `moerc.toml`. See [configfile.md](configfile.md#keymapping-table).

Key notation supports regular keys (`a`, `j`), modifier keys (`C-s`, `M-x`), special keys (`Escape`, `Enter`, `Tab`, `F1`-`F12`), and multi-key sequences in both space-separated (`j j`) and Vim-style concatenated (`jj`) notation.

See [How to use - Runtime Key Mapping](howtouse.md#runtime-key-mapping) for full details.

## Terminal mode

moe has a built-in terminal emulator. You can run a shell or any command inside the editor window.

- `:terminal` - Open an interactive shell (default shell)
- `:terminal command` - Run a specific command (e.g. `:terminal ls -la`)

Terminal mode has two sub-modes:

- **Terminal-Input**: All keystrokes are forwarded to the running shell/command. Press `Ctrl-\ Ctrl-n` to switch to Terminal-Normal sub-mode.
- **Terminal-Normal**: Browse the terminal output. Press `i` or `a` to return to Terminal-Input sub-mode. Press `:` to enter command mode.

When a command finishes (e.g. `:terminal ls`), the output is displayed in a read-only scrollback view (Terminal-Normal sub-mode). When an interactive shell exits, the terminal window is automatically closed.
