# How to use

# Table of Contents

- [Exiting](#exiting)
- [Normal Mode](#normal-mode)
- [Register](#register)
- [Visual Mode](#visual-mode)
- [Replace Mode](#replace-mode)
- [Insert Mode](#insert-mode)
- [Backupmanager Mode](#backupmanager-mode)
- [References Mode](#references-mode)
- [Call Hierarchy Mode](#call-hierarchy-mode)
- [Filer Mode](#filer-mode)
- [Terminal Mode](#terminal-mode)
- [Configuration Mode](#configuration-mode)
- [Command Mode](#command-mode)
- [Runtime Key Mapping](#runtime-key-mapping)


## Exiting


<details open >
  <summary>Check the command line</summary>

| Keys | Description |
|:-----------------------------|:---------------------------|
| <kbd>**:**</kbd> <kbd>**w**</kbd> | Write file |
|<kbd>**:**</kbd> <kbd>**q**</kbd> | Quit |
| <kbd>**:**</kbd> <kbd>**w**</kbd> <kbd>**q**</kbd> | Write and quit |
| <kbd>**:**</kbd> <kbd>**q**</kbd> <kbd>**!**</kbd> | Force quit |
| <kbd>**:**</kbd> <kbd>**q**</kbd> <kbd>**a**</kbd> | Quit all Windows |
| <kbd>**:**</kbd> <kbd>**w**</kbd> <kbd>**q**</kbd> <kbd>**a**</kbd> | Write and quit all Windows |
| <kbd>**:**</kbd> <kbd>**q**</kbd> <kbd>**a**</kbd> <kbd>**!**</kbd> | Force quit all Windows |
|<kbd>**:**</kbd> <kbd>**w**</kbd> <kbd>**!**</kbd> | Force write |
| <kbd>**:**</kbd> <kbd>**w**</kbd> <kbd>**q**</kbd> <kbd>**!**</kbd> | Force write and quit window |

</details>


## Normal mode

<details open>
  <summary>The Default Mode</summary>

| Keys | Description |
|:-----------------------------|:---------------------------|
| <kbd>**h**</kbd><br> | Go Left :arrow_left: |
| <kbd>**j**</kbd><br> | Go Down :arrow_down: |
| <kbd>**k**</kbd><br> | Go Up :arrow_up: |
| <kbd>**l**</kbd><br> | Go Right :arrow_right: |
| <kbd>**w**</kbd><br> | Go forwards to the start of a word :arrow_right: |
| <kbd>**e**</kbd><br> | Go forwards to the end of a word :arrow_right: |
| <kbd>**b**</kbd><br> | Go backwards to the start of a word :arrow_left: |
| <kbd>**{**</kbd><br> |Go previous blank line |
| <kbd>**}**</kbd><br> | Go next blank line |
| <kbd>**r**</kbd><br> | Replace a character at the cursor |
| <kbd>**Page Up**</kbd><br> | Page Up :arrow_up: |
| <kbd>**Page Down**</kbd><br> | Page Down :arrow_down: |
| <kbd>**g**</kbd> <kbd>**g**</kbd><br> | Go to the first line :arrow_up: |
| <kbd>**g**</kbd> <kbd>**_**</kbd><br> | Go to the last non-blank character of the line :arrow_right: |
| <kbd>**G**</kbd><br> |Go to the last line :arrow_down: |
| <kbd>**0**</kbd><br> | Go to the beginning of the line :arrow_left: |
| <kbd>**$**</kbd><br> | Go to the end of the line :arrow_right: |
| <kbd>**^**</kbd><br> | Go to the non-blank character start of line :arrow_left: |
| <kbd>**Ctrl**</kbd> <kbd>**u**</kbd><br> |Half Page Up :arrow_up: |
| <kbd>**Ctrl**</kbd> <kbd>**d**</kbd><br> | Half Page Down :arrow_down: |
| <kbd>**d**</kbd> <kbd>**$**</kbd> OR  <kbd>**D**</kbd><br> | Delete until the end of the line |
| <kbd>**:**</kbd><br> | Start Ex mode |
| <kbd>**u**</kbd><br> | Undo |
| <kbd>**Ctrl**</kbd> <kbd>**r**</kbd><br> | Redo |
| <kbd>**>**</kbd><br> | Indent |
| <kbd>**<**</kbd><br> | Unindent |
| <kbd>**=**</kbd> <kbd>**=**</kbd><br> | Auto Indent |
| <kbd>**d**</kbd> <kbd>**d**</kbd><br> | Delete a line |
| <kbd>**d**</kbd> <kbd>**w**</kbd><br> | Delete a word |
| <kbd>**c**</kbd> <kbd>**i**</kbd> <kbd>**"**</kbd><br> | Delete inside double quotes and enter insert mode |
| <kbd>**c**</kbd> <kbd>**i**</kbd> <kbd>**'**</kbd><br> | Delete inside single quotes and enter insert mode |
| <kbd>**c**</kbd> <kbd>**i**</kbd> <kbd>**(**</kbd> OR <kbd>**c**</kbd> <kbd>**i**</kbd> <kbd>**)**</kbd><br> | Delete inside round brackets and enter insert mode |
| <kbd>**c**</kbd> <kbd>**i**</kbd> <kbd>**[**</kbd> OR <kbd>**c**</kbd> <kbd>**i**</kbd> <kbd>**]**</kbd><br> | Delete inside square brackets and enter insert mode |
| <kbd>**c**</kbd> <kbd>**i**</kbd> <kbd>**{**</kbd> OR <kbd>**c**</kbd> <kbd>**i**</kbd> <kbd>**}**</kbd><br> | Delete inside curly brackets and enter insert mode |
| <kbd>**c**</kbd> <kbd>**i**</kbd> <kbd>**w**</kbd><br> | Delete word and enter insert mode |
| <kbd>**d**</kbd> <kbd>**i**</kbd> <kbd>**"**</kbd><br> | Delete inside double quotes |
| <kbd>**d**</kbd> <kbd>**i**</kbd> <kbd>**'**</kbd><br> | Delete inside single quotes |
| <kbd>**d**</kbd> <kbd>**i**</kbd> <kbd>**(**</kbd> OR <kbd>**d**</kbd> <kbd>**i**</kbd> <kbd>**)**</kbd><br> | Delete inside round brackets |
| <kbd>**d**</kbd> <kbd>**i**</kbd> <kbd>**[**</kbd> OR <kbd>**d**</kbd> <kbd>**i**</kbd> <kbd>**]**</kbd><br> | Delete inside square brackets |
| <kbd>**d**</kbd> <kbd>**i**</kbd> <kbd>**{**</kbd> OR <kbd>**d**</kbd> <kbd>**i**</kbd> <kbd>**}**</kbd><br> | Delete inside curly brackets |
| <kbd>**d**</kbd> <kbd>**i**</kbd> <kbd>**w**</kbd><br> | Delete word |
| <kbd>**x**</kbd><br> | Delete current character |
| <kbd>**S**</kbd> OR <kbd>**c**</kbd> <kbd>**c**</kbd><br> | Delete the characters in current line and start insert mode |
| <kbd>**y**</kbd> <kbd>**y**</kbd> OR <kbd>**Y**</kbd><br> |Copy a line |
| <kbd>**p**</kbd><br> | Paste the clipboard |
| <kbd>**n**</kbd><br> | Search forwards |
| <kbd>**N**</kbd><br> | Search backwards |
| <kbd> * </kbd><br> | Search forwards for the word under cursor |
| <kbd>**#**</kbd><br> | Search backwards for the word under cursor |
| <kbd>**f**</kbd><br> | Jump to next occurrence |
| <kbd>**F**</kbd><br> |Jump to previous occurrence |
| <kbd>**z**</kbd> <kbd>**t**</kbd><br> | Scroll the screen so the cursor is at the top |
| <kbd>**z**</kbd> <kbd>**b**</kbd><br> | Scroll the screen so the cursor is at the bottom |
| <kbd>**z**</kbd> <kbd>**.**</kbd><br> | Center the screen on the cursor |
| <kbd>**Z**</kbd> <kbd>**Z**</kbd><br> | Write current file and exit |
| <kbd>**Z**</kbd> <kbd>**Q**</kbd><br> | Same as `:q!` |
| <kbd>**Ctrl**</kbd> <kbd>**w**</kbd> <kbd>**j**</kbd><br> | Move to the previous window |
| <kbd>**Ctrl**</kbd> <kbd>**w**</kbd> <kbd>**k**</kbd><br> | Move to the next window |
| <kbd>**Ctrl**</kbd> <kbd>**w**</kbd> <kbd>**c**</kbd><br> | Close current window |
| <kbd>**?**</kbd><br> |`keyword` Search backwards |
| <kbd>**/**</kbd><br> |`keyword` Search forwards |
| <kbd>**\\**</kbd> <kbd>**r**</kbd><br> | Quick Run |
| <kbd>**s**</kbd> OR <kbd>**c**</kbd><kbd>**u**</kbd><br> | Delete current character and enter insert mode |
| <kbd>**y**</kbd><kbd>**{**</kbd><br> | Yank to the previous blank line |
| <kbd>**y**</kbd><kbd>**}**</kbd><br> | Yank to the next blank line |
| <kbd>**y**</kbd><kbd>**l**</kbd><br> | Yank a character |
| <kbd>**X**</kbd> OR <kbd>**d**</kbd><kbd>**h**</kbd><br> | Cut a character before cursor |
| <kbd>**g**</kbd><kbd>**a**</kbd><br> | Show current character info |
| <kbd>**t**</kbd><kbd>**x**</kbd><br> | Move to the left of the next ```x``` (any character) on the current line |
| <kbd>**T**</kbd><kbd>**x**</kbd><br> | Move to the right of the back ```x ``` (any character) on the current line |
| <kbd>**y**</kbd><kbd>**t**</kbd> <kbd>**Any key**</kbd><br> | Yank characters to an any character |
| <kbd>**c**</kbd><kbd>**f**</kbd> <kbd>**Any key**</kbd><br> | Delete characters to an any character and enter insert mode |
| <kbd>**H**</kbd></br> | Move to the top line of the screen |
| <kbd>**M**</kbd></br> | Move to the center line of the screen |
| <kbd>**L**</kbd></br> | Move to the bottom line of the screen |
| <kbd>**%**</kbd></br> | Move to matching pair of paren |
| <kbd>**q**</kbd> <kbd>**Any key**</kbd></br> | Start recording operations for Macros |
| <kbd>**q**</kbd></br> | Stop recording operations |
| <kbd>**@**</kbd> <kbd>**Any key**</kbd></br> | Execute a macro |
| <kbd>**c**</kbd> <kbd>**t**</kbd> <kbd>**Any Key**</kbd></br> | Delete characters until the any key and enter Insert mode |
| <kbd>**d**</kbd> <kbd>**t**</kbd> <kbd>**Any Key**</kbd></br> | Delete characters until the any key |
| <kbd>**.**</kbd></br> | Repeat the last normal mode command |
| <kbd>**K**</kbd></br> | Hover (LSP) |
| <kbd>**g**</kbd> <kbd>**c**</kbd></br> | Goto Declaration (LSP) |
| <kbd>**g**</kbd> <kbd>**d**</kbd></br> | Goto Definition (LSP) |
| <kbd>**g**</kbd> <kbd>**y**</kbd></br> | Goto TypeDefinition (LSP) |
| <kbd>**g**</kbd> <kbd>**i**</kbd></br> | Goto Implementation (LSP) |
| <kbd>**g**</kbd> <kbd>**r**</kbd></br> | Open References mode (LSP Find References) |
| <kbd>**g**</kbd> <kbd>**h**</kbd></br> | Open Call Hierarchy Viewer (LSP Call Hierarchy) |
| <kbd>**g**</kbd> <kbd>**L**</kbd></br> | Code Lens (LSP) |
| <kbd>**Space**</kbd> <kbd>**r**</kbd></br> | Rename (LSP) |
| <kbd>**z**</kbd> <kbd>**d**</kbd></br> | Delete fold lines |
| <kbd>**z**</kbd> <kbd>**R**</kbd></br> | Delete fold lines |
| <kbd>**Ctrl**</kbd> <kbd>**s**</kbd></br> | Selection Range (LSP) |
| <kbd>**Space**</kbd> <kbd>**o**</kbd></br> | Document Symbol (LSP) |
| <kbd>**g**</kbd> <kbd>**t**</kbd></br> | Switch to the next buffer |
| <kbd>**g**</kbd> <kbd>**T**</kbd></br> | Switch to the previous buffer |
| <kbd>**Ctrl**</kbd> <kbd>**o**</kbd></br> | Jump Back (Jumplist) |
| <kbd>**Ctrl**</kbd> <kbd>**i**</kbd></br> | Jump Forward (Jumplist) |

</details>

## Register

<details open>
  <summary>Register operations</summary>

| Keys | Description |
|:-----------------------------|:---------------------------|
| <kbd>**"**</kbd> <kbd>**register name**</kbd> <kbd>**y**</kbd> <kbd>**y**</kbd> | Yank a line to a named register |
| <kbd>**"**</kbd> <kbd>**register name**</kbd> <kbd>**y**</kbd> <kbd>**l**</kbd> | Yank a character to a named register |
| <kbd>**"**</kbd> <kbd>**register name**</kbd> <kbd>**y**</kbd> <kbd>**w**</kbd> | Yank a word to a named register |
| <kbd>**"**</kbd> <kbd>**register name**</kbd> <kbd>**y**</kbd> <kbd>**{**</kbd> | Yank to the previous blank line to a named register |
| <kbd>**"**</kbd> <kbd>**register name**</kbd> <kbd>**y**</kbd> <kbd>**}**</kbd> | Yank to the next blank line to a named register |
| <kbd>**"**</kbd> <kbd>**register name**</kbd> <kbd>**p**</kbd> | Paste from a named register after cursor |
| <kbd>**"**</kbd> <kbd>**register name**</kbd> <kbd>**P**</kbd> | Paste from a named register before cursor |
| <kbd>**"**</kbd> <kbd>**register name**</kbd> <kbd>**d**</kbd> <kbd>**d**</kbd> | Delete a line to a named register |
| <kbd>**"**</kbd> <kbd>**register name**</kbd> <kbd>**d**</kbd> <kbd>**w**</kbd> | Delete a word to a named register |
| <kbd>**"**</kbd> <kbd>**register name**</kbd> <kbd>**d**</kbd> <kbd>**$**</kbd> | Delete to end of line to a named register |
| <kbd>**"**</kbd> <kbd>**register name**</kbd> <kbd>**d**</kbd> <kbd>**0**</kbd> | Delete to beginning of line to a named register |
| <kbd>**"**</kbd> <kbd>**register name**</kbd> <kbd>**d**</kbd> <kbd>**G**</kbd> | Delete to end of file to a named register |
| <kbd>**"**</kbd> <kbd>**register name**</kbd> <kbd>**d**</kbd> <kbd>**g**</kbd> <kbd>**g**</kbd> | Delete to beginning of file to a named register |
| <kbd>**"**</kbd> <kbd>**register name**</kbd> <kbd>**d**</kbd> <kbd>**{**</kbd> | Delete to the previous blank line to a named register |
| <kbd>**"**</kbd> <kbd>**register name**</kbd> <kbd>**d**</kbd> <kbd>**}**</kbd> | Delete to the next blank line to a named register |
| <kbd>**"**</kbd> <kbd>**register name**</kbd> <kbd>**d**</kbd> <kbd>**i**</kbd> <kbd>**any key**</kbd> | Delete inside to a named register |
| <kbd>**"**</kbd> <kbd>**register name**</kbd> <kbd>**d**</kbd> <kbd>**h**</kbd> | Delete a character before cursor to a named register |
| <kbd>**"**</kbd> <kbd>**register name**</kbd> <kbd>**c**</kbd> <kbd>**l**</kbd> OR <kbd>**"**</kbd> <kbd>**register name**</kbd> <kbd>**s**</kbd> | Change a character to a named register |
| <kbd>**"**</kbd> <kbd>**register name**</kbd> <kbd>**c**</kbd> <kbd>**i**</kbd> <kbd>**any key**</kbd> | Change inside to a named register |
 
</details>

## Visual mode

<details open>
  <summary>Visual Selection</summary>

| Keys | Description |
|:-----------------------------|:---------------------------|
| <kbd>**Esc**</kbd><br> | Enter Normal mode |
| <kbd>**d**</kbd> OR <kbd>**x**</kbd><br> | Delete characters |
| <kbd>**y**</kbd><br> | Copy characters |
| <kbd>**r**</kbd><br> | Replace character |
| <kbd>**J**</kbd><br> | Join lines |
| <kbd>**u**</kbd><br> | Convert to Lowercase |
| <kbd>**U**</kbd><br> | Convert to Uppercase |
| <kbd>**>**</kbd><br> | Indent |
| <kbd>**<**</kbd><br> | Unindent |
| <kbd>**~**</kbd><br> | Toggle case |
| <kbd>**Ctrl**</kbd> <kbd>**a**</kbd><br> | Increase number |
| <kbd>**Ctrl**</kbd> <kbd>**x**</kbd><br> | Decrease number |
| <kbd>**I**</kbd><br> | Insert characters to multiple lines |
| <kbd>**z**</kbd> <kbd>**f**</kbd><br> | Fold lines |
| <kbd>**Ctrl**</kbd> <kbd>**s**</kbd></br> | Selection Range (LSP) |

</details>

## Replace mode

<details open>
  <summary>Replace Text</summary>
  
|                               |                             |                               |                             |
|:-----------------------------:|:---------------------------:|:-----------------------------:|:---------------------------:|
| <kbd>**Esc**</kbd> Go to Normal mode | <kbd>**Backspace**</kbd> Undo |  |  |

</details>


## Insert mode

<details open>
  <summary>Insert Text</summary>

| Keys | Description |
|:-----------------------------|:---------------------------|
| <kbd>**Esc**</kbd><br> | Enter Normal mode |
| <kbd>**Ctrl**</kbd> <kbd>**e**</kbd><br> | Insert the character which is below the cursor |
| <kbd>**Ctrl**</kbd> <kbd>**y**</kbd><br> | Insert the character which is above the cursor |
| <kbd>**Ctrl**</kbd> <kbd>**i**</kbd><br> | Insert a Tab |
| <kbd>**Ctrl**</kbd> <kbd>**h**</kbd> OR <kbd>**Backspace**</kbd><br> | Delete the character before the cursor |
| <kbd>**Ctrl**</kbd> <kbd>**t**</kbd><br> | Indent |
| <kbd>**Ctrl**</kbd> <kbd>**d**</kbd><br> | UnIndent |
| <kbd>**Ctrl**</kbd> <kbd>**w**</kbd><br> | Delete the word before the cursor |
| <kbd>**Ctrl**</kbd> <kbd>**u**</kbd><br> | Delete characters before the cursor |
| <kbd>**Ctrl**</kbd> <kbd>**r**</kbd><br> | Signature Help (LSP) |

</details>


## Backupmanager mode

<details open>
  <summary>Backup File Manager</summary>

| Keys | Description |
|:-----------------------------|:---------------------------|
| <kbd>**Enter**</kbd><br> | Open Diff |
| <kbd>**R**</kbd><br> | Restore Backup file |
| <kbd>**D**</kbd><br> | Delete Backup file |
| <kbd>**r**</kbd><br> | Reload Backup file |

</details>


## References mode

<details open>
  <summary>References mode</summary>

| Keys | Description |
|:-----------------------------|:---------------------------|
| <kbd>**Enter**</kbd><br> | Go to the destination |
| <kbd>**ESC**</kbd><br> | Quit References mode |

</details>

## Call Hierarchy mode

<details open>
  <summary>Call Hierarchy</summary>

| Keys | Description |
|:-----------------------------|:---------------------------|
| <kbd>**Enter**</kbd><br> | Go to the destination |
| <kbd>**i**</kbd><br> | Incoming Call (LSP) |
| <kbd>**o**</kbd><br> | Outgoing Call (LSP)  |

</details>

## Filer mode

<details open>
  <summary>File Manager</summary>

| Keys | Description |
|:-----------------------------|:---------------------------|
| <kbd>**D**</kbd><br> | Delete file |
| <kbd>**i**</kbd><br> | Detail Information |
| <kbd>**v**</kbd><br> | Split window and open file or directory |

</details>


## Terminal mode

<details open>
  <summary>Built-in Terminal Emulator</summary>

### Terminal-Input sub-mode (default)

All keystrokes are forwarded to the running shell/command.

| Keys | Description |
|:-----------------------------|:---------------------------|
| <kbd>**Ctrl**</kbd> <kbd>**\\**</kbd> <kbd>**Ctrl**</kbd> <kbd>**n**</kbd><br> | Switch to Terminal-Normal sub-mode |

### Terminal-Normal sub-mode

| Keys | Description |
|:-----------------------------|:---------------------------|
| <kbd>**i**</kbd><br> | Return to Terminal-Input sub-mode |
| <kbd>**a**</kbd><br> | Return to Terminal-Input sub-mode |
| <kbd>**:**</kbd><br> | Enter command mode |

</details>

## Configuration mode
<details open>
  <summary>Configuration mode</summary>

| Keys | Description |
|:-----------------------------|:---------------------------|
| <kbd>**w**</kbd><br> | Save the current configs to the configuration file |

</details>

## Command mode

<details open>
  <summary>Command mode</summary>

| Command| Description |
|:-----------------------------|:---------------------------|
| `number`          | Jump to line number; e.g. `:10` |
| `! shell command` | Shell command execution |
| `bg`              | Pause the editor and show the recent terminal output |
| `man arguments`   | Show the given UNIX manual page, if available; e.g. `:man man` |
| `e filename` | Open file |
| `ene` | Create new empty buffer |
| `new` | Create new empty buffer in split window horizontally |
| `vnew` | Create new empty buffer in split window vertically |
| `%s/keyword1/keyword2/` | Replace text (normal mode only) |
| `ls` | Display all buffer |
| `bprev` | Switch to the previous buffer |
| `bnext` | Switch to the next buffer |
| `bfirst` | Switch to the first buffer |
| `blast` | Switch to the last buffer |
| `bd` or `bd number` | Delete buffer |
| `buf` | Open buffer manager |
| `vs` | Vertical split window |
| `vs filename` | Open in vertical split window |
| `sv` | Horizontal split window |
| `sp filename` | Open in horizontal split window |
| `livereload on` or `livereload off` | Change setting of live reload of configuration file |
| `theme themeName` | Change color theme : Example `theme dark` |
| `tab on` or `tab off` | Change setting to tab line |
| `syntax on` or `syntax off` | Change setting to syntax highlighting |
| `tabstop number` | Change setting to tabStop : Example `tabstop 2`  |
| `paren on` or `paren off` | Change setting to auto close paren |
| `indent on` or `indent off` | Change sestting to auto indent |
| `linenum on` or `linenum off` | Change setting to display line number |
| `statusLine on` or `statusLine off` | Change setting to display status line|
| `realtimesearch on` or `realtimesearch off` | Change setting to real-time search |
| `deleteparen on` or `deleteparen off` | Change setting to auto delete paren |
| `smoothscroll on` or `smoothscroll off` | Change setting to smooth scroll |
| `highlightcurrentword on` or `highlightcurrentword off` | Change setting to highlight other uses of the current word |
| `clipboard on` or `clipboard off` | Change setting to system clipboard |
| `highlightfullspace on` or `highlightfullspace off` | Change setting to highlight full width space |
| `buildonsave on` or `buildonsave off` | Change setting to build on save |
| `indentationlines on`  or `indentationlines off` | Change setting to indentation lines |
| `showGitInactive on` or `showGitInactive off` | Change status line setting to show/hide git branch name in inactive window |
| `nohlsearch` | Turn off highlights |
| `icon` | Setting show/hidden icons in filer mode |
| `stripwhitespace` | Delete trailing spaces |
| `ignorecase` | Change setting to ignorecase |
| `smartcase` | Change setting to smartcase |
| `cursorline on` or `cursorline off` | Change the highlight setting of the current line |
| `build` | Build the current buffer |
| `lspfold` | LSP Folding Range |
| `lspformat` | LSP Document Formatting |
| `log` | Open a log viewer for editor log |
| `lsplog` | Open a log viewer for LSP log |
| `lsprestart` | Restart the current LSP server |
| `help` | Open help |
| `putconfigfile` | Put a sample configuration file in ~/.config/moe |
| `run` | Quick run |
| `recent` | Open recent file selection mode (Only supported on Linux) |
| `backup` | Open backup manager |
| `config` | Open configuration mode |
| `debug` | Open debug mode |
| `jump` | Open Jump list viewer |
| `terminal` | Open terminal emulator (default shell) |
| `terminal command` | Run command in terminal emulator |

</details>

### Runtime Key Mapping

<details open>
  <summary>Runtime key mapping commands</summary>

Map, unmap, and clear runtime key mappings. All mappings are non-recursive (noremap).
Mappings are session-only and not persisted across restarts.

| Command| Description |
|:-----------------------------|:---------------------------|
| `nmap {lhs} {rhs}` | Map keys in Normal mode |
| `imap {lhs} {rhs}` | Map keys in Insert mode |
| `vmap {lhs} {rhs}` | Map keys in Visual modes |
| `rmap {lhs} {rhs}` | Map keys in Replace mode |
| `map {lhs} {rhs}` | Map keys in all modes |
| `nunmap {lhs}` | Remove mapping in Normal mode |
| `iunmap {lhs}` | Remove mapping in Insert mode |
| `vunmap {lhs}` | Remove mapping in Visual modes |
| `runmap {lhs}` | Remove mapping in Replace mode |
| `unmap {lhs}` | Remove mapping in all modes |
| `nmapclear` | Clear all Normal mode mappings |
| `imapclear` | Clear all Insert mode mappings |
| `vmapclear` | Clear all Visual mode mappings |
| `rmapclear` | Clear all Replace mode mappings |
| `mapclear` | Clear all mode mappings |

`noremap`, `nnoremap`, `inoremap`, `vnoremap` are aliases (all mappings are non-recursive).

**Key notation:**

| Notation | Meaning |
|:----|:----|
| `a`, `j`, `0` | Regular keys |
| `C-s`, `M-x` | Modifier keys (`C`=Ctrl, `M`=Alt, `S`=Shift) |
| `Escape`, `Enter`, `Tab` | Special keys |
| `Up`, `Down`, `F1`-`F12` | Arrow and function keys |
| `Space` | Space key |
| `j j`, `g g` | Multi-key sequences (space-separated) |
| `jj`, `gg` | Vim-style concatenated keys (equivalent to `j j`, `g g`) |

`{rhs}` can be a command name or a key sequence (e.g. `Escape`).

**Examples:**

```
:nmap C-s save-and-quit  " Ctrl-S saves and quits (Normal mode)
:imap jj Escape          " jj exits Insert mode
:nmap C-a g g            " Ctrl-A goes to first line
:vmap C-c Escape         " Ctrl-C exits Visual mode
:nunmap C-s              " Remove Ctrl-S mapping in Normal mode
:nmapclear               " Clear all Normal mode runtime mappings
```

</details>

[Go To Top](#table-of-contents)
