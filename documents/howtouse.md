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
- [FileTree Mode](#filetree-mode)
- [Buffer Manager Mode](#buffer-manager-mode)
- [Bookmark Manager Mode](#bookmark-manager-mode)
- [Document Symbol Mode](#document-symbol-mode)
- [Log Viewer Mode](#log-viewer-mode)
- [Recent File Mode](#recent-file-mode)
- [Debug Mode](#debug-mode)
- [Terminal Mode](#terminal-mode)
- [Configuration Mode](#configuration-mode)
- [Command Mode](#command-mode)
- [Runtime Key Mapping](#runtime-key-mapping)


## Exiting


<details open >
  <summary>Check the command line</summary>

<!-- AUTO-GEN:start Exiting -->
| Keys | Description |
|:---|:---|
| <kbd>**:**</kbd> <kbd>**w**</kbd> | Write file |
| <kbd>**:**</kbd> <kbd>**q**</kbd> | Quit |
| <kbd>**:**</kbd> <kbd>**w**</kbd> <kbd>**q**</kbd> | Write and quit |
| <kbd>**:**</kbd> <kbd>**q**</kbd> <kbd>**!**</kbd> | Force quit |
| <kbd>**:**</kbd> <kbd>**q**</kbd> <kbd>**a**</kbd> | Quit all windows |
| <kbd>**:**</kbd> <kbd>**w**</kbd> <kbd>**q**</kbd> <kbd>**a**</kbd> | Write and quit all windows |
| <kbd>**:**</kbd> <kbd>**q**</kbd> <kbd>**a**</kbd> <kbd>**!**</kbd> | Force quit all windows |
| <kbd>**:**</kbd> <kbd>**w**</kbd> <kbd>**!**</kbd> | Force write |
| <kbd>**:**</kbd> <kbd>**w**</kbd> <kbd>**q**</kbd> <kbd>**!**</kbd> | Force write and quit window |
| <kbd>**:**</kbd> <kbd>**w**</kbd> <kbd>**q**</kbd> <kbd>**a**</kbd> <kbd>**!**</kbd> | Force write and quit all windows |
| <kbd>**:**</kbd> <kbd>**c**</kbd> <kbd>**q**</kbd> | Quit with non-zero exit code |
<!-- AUTO-GEN:end Exiting -->

</details>


## Normal mode

<details open>
  <summary>The Default Mode</summary>

<!-- AUTO-GEN:start NormalMode -->
| Keys | Description |
|:---|:---|
| <kbd>**h**</kbd> | Go left |
| <kbd>**j**</kbd> | Go down |
| <kbd>**Ctrl**</kbd> <kbd>**j**</kbd> | Go down |
| <kbd>**k**</kbd> | Go up |
| <kbd>**l**</kbd> | Go right |
| <kbd>**w**</kbd> | Go forwards to the start of a word |
| <kbd>**e**</kbd> | Go forwards to the end of a word |
| <kbd>**g**</kbd> <kbd>**e**</kbd> | Go backwards to the end of a word |
| <kbd>**b**</kbd> | Go backwards to the start of a word |
| <kbd>**r**</kbd> | Replace a character at the cursor |
| <kbd>**Page Up**</kbd> | Page Up |
| <kbd>**Page Down**</kbd> | Page Down |
| <kbd>**g**</kbd> <kbd>**g**</kbd> | Go to the first line |
| <kbd>**g**</kbd> <kbd>**_**</kbd> | Go to the last non-blank character of the line |
| <kbd>**g**</kbd> <kbd>**;**</kbd> | Go to the previous change position |
| <kbd>**g**</kbd> <kbd>**,**</kbd> | Go to the next change position |
| <kbd>**G**</kbd> | Go to the last line |
| <kbd>**0**</kbd> | Go to the first character of the line |
| <kbd>**$**</kbd> | Go to the end of the line |
| <kbd>**^**</kbd> | Go to the first non-blank character of the line |
| <kbd>**{**</kbd> | Go to the previous blank line |
| <kbd>**}**</kbd> | Go to the next blank line |
| <kbd>**H**</kbd> | Move to the top line of the screen |
| <kbd>**M**</kbd> | Move to the center line of the screen |
| <kbd>**L**</kbd> | Move to the bottom line of the screen |
| <kbd>**Ctrl**</kbd> <kbd>**b**</kbd> | Page Up |
| <kbd>**Ctrl**</kbd> <kbd>**f**</kbd> | Page Down |
| <kbd>**Ctrl**</kbd> <kbd>**u**</kbd> | Half Page Up |
| <kbd>**Ctrl**</kbd> <kbd>**d**</kbd> | Half Page Down |
| <kbd>**%**</kbd> | Move to matching pair of paren |
| <kbd>**d**</kbd> <kbd>**$**</kbd> OR <kbd>**D**</kbd> | Delete until the end of the line |
| <kbd>**C**</kbd> | Change until the end of the line |
| <kbd>**y**</kbd> <kbd>**y**</kbd> OR <kbd>**Y**</kbd> | Copy a line |
| <kbd>**y**</kbd> <kbd>**{**</kbd> | Yank to the previous blank line |
| <kbd>**y**</kbd> <kbd>**}**</kbd> | Yank to the next blank line |
| <kbd>**y**</kbd> <kbd>**l**</kbd> | Yank a character |
| <kbd>**y**</kbd> <kbd>**t**</kbd> <kbd>**Any key**</kbd> | Yank characters to a any character |
| <kbd>**p**</kbd> | Paste the clipboard |
| <kbd>**P**</kbd> | Paste the clipboard before the cursor |
| <kbd>**n**</kbd> | Search forwards |
| <kbd>**N**</kbd> | Search backwards |
| <kbd>**g**</kbd> <kbd>**n**</kbd> | Go to next search match and select it visually |
| <kbd>**g**</kbd> <kbd>**N**</kbd> | Go to previous search match and select it visually |
| <kbd>**d**</kbd> <kbd>**g**</kbd> <kbd>**n**</kbd> | Delete next search match |
| <kbd>**d**</kbd> <kbd>**g**</kbd> <kbd>**N**</kbd> | Delete previous search match |
| <kbd>**]**</kbd> <kbd>**c**</kbd> | Jump to next git change hunk |
| <kbd>**[**</kbd> <kbd>**c**</kbd> | Jump to previous git change hunk |
| <kbd>**]**</kbd> <kbd>**x**</kbd> | Jump to next git merge conflict block |
| <kbd>**[**</kbd> <kbd>**x**</kbd> | Jump to previous git merge conflict block |
| <kbd>**:**</kbd> | Start command mode |
| <kbd>**u**</kbd> | Undo |
| <kbd>**Ctrl**</kbd> <kbd>**r**</kbd> | Redo |
| <kbd>**Ctrl**</kbd> <kbd>**a**</kbd> | Increase number under cursor |
| <kbd>**Ctrl**</kbd> <kbd>**x**</kbd> | Decrease number under cursor |
| <kbd>**>**</kbd> | Indent |
| <kbd>**<**</kbd> | Unindent |
| <kbd>**=**</kbd> <kbd>**=**</kbd> | Auto indent |
| <kbd>**J**</kbd> | Join lines |
| <kbd>**d**</kbd> <kbd>**d**</kbd> | Delete a line |
| <kbd>**x**</kbd> | Delete current character |
| <kbd>**X**</kbd> OR <kbd>**d**</kbd> <kbd>**h**</kbd> | Delete the character before the cursor |
| <kbd>**~**</kbd> | Toggle case of character under cursor |
| <kbd>**g**</kbd> <kbd>**u**</kbd> | Lowercase (operator) |
| <kbd>**g**</kbd> <kbd>**U**</kbd> | Uppercase (operator) |
| <kbd>**S**</kbd> OR <kbd>**c**</kbd> <kbd>**c**</kbd> | Delete the characters in the current line and start insert mode |
| <kbd>**s**</kbd> OR <kbd>**c**</kbd> <kbd>**l**</kbd> | Delete the current character and enter insert mode |
| <kbd>**c**</kbd> <kbd>**i**</kbd> <kbd>**"**</kbd> | Delete the inside of double quotes and enter insert mode |
| <kbd>**c**</kbd> <kbd>**i**</kbd> <kbd>**'**</kbd> | Delete the inside of single quotes and enter insert mode |
| <kbd>**c**</kbd> <kbd>**i**</kbd> <kbd>**w**</kbd> | Delete the current word and enter insert mode |
| <kbd>**c**</kbd> <kbd>**i**</kbd> <kbd>**W**</kbd> | Delete the current WORD and enter insert mode |
| <kbd>**c**</kbd> <kbd>**i**</kbd> <kbd>**(**</kbd> OR <kbd>**c**</kbd> <kbd>**i**</kbd> <kbd>**)**</kbd> | Delete the inside of round brackets and enter insert mode |
| <kbd>**c**</kbd> <kbd>**i**</kbd> <kbd>**[**</kbd> OR <kbd>**c**</kbd> <kbd>**i**</kbd> <kbd>**]**</kbd> | Delete the inside of square brackets and enter insert mode |
| <kbd>**c**</kbd> <kbd>**i**</kbd> <kbd>**{**</kbd> OR <kbd>**c**</kbd> <kbd>**i**</kbd> <kbd>**}**</kbd> | Delete the inside of curly brackets and enter insert mode |
| <kbd>**c**</kbd> <kbd>**a**</kbd> <kbd>**"**</kbd> | Delete around double quotes and enter insert mode |
| <kbd>**c**</kbd> <kbd>**a**</kbd> <kbd>**'**</kbd> | Delete around single quotes and enter insert mode |
| <kbd>**c**</kbd> <kbd>**a**</kbd> <kbd>**w**</kbd> | Delete a word (with surrounding whitespace) and enter insert mode |
| <kbd>**c**</kbd> <kbd>**a**</kbd> <kbd>**W**</kbd> | Delete a WORD (with surrounding whitespace) and enter insert mode |
| <kbd>**c**</kbd> <kbd>**a**</kbd> <kbd>**(**</kbd> OR <kbd>**c**</kbd> <kbd>**a**</kbd> <kbd>**)**</kbd> | Delete around round brackets and enter insert mode |
| <kbd>**c**</kbd> <kbd>**a**</kbd> <kbd>**[**</kbd> OR <kbd>**c**</kbd> <kbd>**a**</kbd> <kbd>**]**</kbd> | Delete around square brackets and enter insert mode |
| <kbd>**c**</kbd> <kbd>**a**</kbd> <kbd>**{**</kbd> OR <kbd>**c**</kbd> <kbd>**a**</kbd> <kbd>**}**</kbd> | Delete around curly brackets and enter insert mode |
| <kbd>**c**</kbd> <kbd>**f**</kbd> <kbd>**Any key**</kbd> | Delete characters to the any character and enter insert mode |
| <kbd>**c**</kbd> <kbd>**t**</kbd> <kbd>**Any key**</kbd> | Delete characters until the character and enter insert mode |
| <kbd>**d**</kbd> <kbd>**i**</kbd> <kbd>**"**</kbd> | Delete the inside of double quotes |
| <kbd>**d**</kbd> <kbd>**i**</kbd> <kbd>**'**</kbd> | Delete the inside of single quotes |
| <kbd>**d**</kbd> <kbd>**i**</kbd> <kbd>**w**</kbd> | Delete the current word |
| <kbd>**d**</kbd> <kbd>**i**</kbd> <kbd>**W**</kbd> | Delete the current WORD |
| <kbd>**d**</kbd> <kbd>**i**</kbd> <kbd>**(**</kbd> OR <kbd>**d**</kbd> <kbd>**i**</kbd> <kbd>**)**</kbd> | Delete the inside of round brackets |
| <kbd>**d**</kbd> <kbd>**i**</kbd> <kbd>**[**</kbd> OR <kbd>**d**</kbd> <kbd>**i**</kbd> <kbd>**]**</kbd> | Delete the inside of square brackets |
| <kbd>**d**</kbd> <kbd>**i**</kbd> <kbd>**{**</kbd> OR <kbd>**d**</kbd> <kbd>**i**</kbd> <kbd>**}**</kbd> | Delete the inside of curly brackets |
| <kbd>**d**</kbd> <kbd>**a**</kbd> <kbd>**"**</kbd> | Delete around double quotes (including quotes) |
| <kbd>**d**</kbd> <kbd>**a**</kbd> <kbd>**'**</kbd> | Delete around single quotes (including quotes) |
| <kbd>**d**</kbd> <kbd>**a**</kbd> <kbd>**w**</kbd> | Delete a word (including surrounding whitespace) |
| <kbd>**d**</kbd> <kbd>**a**</kbd> <kbd>**W**</kbd> | Delete a WORD (including surrounding whitespace) |
| <kbd>**d**</kbd> <kbd>**a**</kbd> <kbd>**(**</kbd> OR <kbd>**d**</kbd> <kbd>**a**</kbd> <kbd>**)**</kbd> | Delete around round brackets (including brackets) |
| <kbd>**d**</kbd> <kbd>**a**</kbd> <kbd>**[**</kbd> OR <kbd>**d**</kbd> <kbd>**a**</kbd> <kbd>**]**</kbd> | Delete around square brackets (including brackets) |
| <kbd>**d**</kbd> <kbd>**a**</kbd> <kbd>**{**</kbd> OR <kbd>**d**</kbd> <kbd>**a**</kbd> <kbd>**}**</kbd> | Delete around curly brackets (including brackets) |
| <kbd>**d**</kbd> <kbd>**t**</kbd> <kbd>**Any key**</kbd> | Delete characters until the character |
| <kbd>**y**</kbd> <kbd>**i**</kbd> <kbd>**w**</kbd> | Yank the current word |
| <kbd>**y**</kbd> <kbd>**i**</kbd> <kbd>**W**</kbd> | Yank the current WORD |
| <kbd>**y**</kbd> <kbd>**i**</kbd> <kbd>**"**</kbd> | Yank the inside of double quotes |
| <kbd>**y**</kbd> <kbd>**i**</kbd> <kbd>**'**</kbd> | Yank the inside of single quotes |
| <kbd>**y**</kbd> <kbd>**i**</kbd> <kbd>**(**</kbd> OR <kbd>**y**</kbd> <kbd>**i**</kbd> <kbd>**)**</kbd> | Yank the inside of round brackets |
| <kbd>**y**</kbd> <kbd>**i**</kbd> <kbd>**[**</kbd> OR <kbd>**y**</kbd> <kbd>**i**</kbd> <kbd>**]**</kbd> | Yank the inside of square brackets |
| <kbd>**y**</kbd> <kbd>**i**</kbd> <kbd>**{**</kbd> OR <kbd>**y**</kbd> <kbd>**i**</kbd> <kbd>**}**</kbd> | Yank the inside of curly brackets |
| <kbd>**y**</kbd> <kbd>**a**</kbd> <kbd>**w**</kbd> | Yank a word (including surrounding whitespace) |
| <kbd>**y**</kbd> <kbd>**a**</kbd> <kbd>**W**</kbd> | Yank a WORD (including surrounding whitespace) |
| <kbd>*****</kbd> | Search forwards for the word under cursor |
| <kbd>**#**</kbd> | Search backwards for the word under cursor |
| <kbd>**f**</kbd> | Move to next any character on the current line |
| <kbd>**F**</kbd> | Move to previous any character on the current line |
| <kbd>**t**</kbd> | Move to the left of the any character on the current line |
| <kbd>**T**</kbd> | Move to the right of the back any character on the current line |
| <kbd>**;**</kbd> | Repeat last f/F/t/T |
| <kbd>**,**</kbd> | Repeat last f/F/t/T in reverse |
| <kbd>**Ctrl**</kbd> <kbd>**w**</kbd> <kbd>**k**</kbd> | Move to the next window |
| <kbd>**Ctrl**</kbd> <kbd>**w**</kbd> <kbd>**j**</kbd> | Move to the previous window |
| <kbd>**z**</kbd> <kbd>**t**</kbd> | Scroll the screen so the cursor is at the top |
| <kbd>**z**</kbd> <kbd>**b**</kbd> | Scroll the screen so the cursor is at the bottom |
| <kbd>**z**</kbd> <kbd>**.**</kbd> | Center the screen on the cursor |
| <kbd>**z**</kbd> <kbd>**z**</kbd> | Center the screen on the cursor |
| <kbd>**Z**</kbd> <kbd>**Z**</kbd> | Write current file and exit |
| <kbd>**Z**</kbd> <kbd>**Q**</kbd> | Same as :q! |
| <kbd>**Ctrl**</kbd> <kbd>**w**</kbd> <kbd>**c**</kbd> | Close current window |
| <kbd>**Ctrl**</kbd> <kbd>**w**</kbd> <kbd>**+**</kbd> | Increase window height |
| <kbd>**Ctrl**</kbd> <kbd>**w**</kbd> <kbd>**-**</kbd> | Decrease window height |
| <kbd>**Ctrl**</kbd> <kbd>**w**</kbd> <kbd>**>**</kbd> | Increase window width |
| <kbd>**Ctrl**</kbd> <kbd>**w**</kbd> <kbd>**<**</kbd> | Decrease window width |
| <kbd>**Ctrl**</kbd> <kbd>**w**</kbd> <kbd>**=**</kbd> | Equalize window sizes |
| <kbd>**Ctrl**</kbd> <kbd>**w**</kbd> <kbd>**x**</kbd> | Swap window with next window |
| <kbd>**/**</kbd> | Search forwards |
| <kbd>**?**</kbd> | Search backwards |
| <kbd>**\\**</kbd> <kbd>**r**</kbd> | QuickRun |
| <kbd>**g**</kbd> <kbd>**a**</kbd> | Show current character info |
| <kbd>**.**</kbd> | Repeat the last normal mode command |
| <kbd>**q**</kbd> <kbd>**Any key**</kbd> | Start recording operations for Macros |
| <kbd>**q**</kbd> | Stop recoding operations |
| <kbd>**@**</kbd> <kbd>**Any key**</kbd> | Exec a macro |
| <kbd>**@**</kbd> <kbd>**:**</kbd> | Repeat the last command mode command |
| <kbd>**K**</kbd> | Hover (LSP) |
| <kbd>**g**</kbd> <kbd>**c**</kbd> | Goto Declaration (LSP) |
| <kbd>**g**</kbd> <kbd>**d**</kbd> | Goto Definition (LSP) |
| <kbd>**g**</kbd> <kbd>**y**</kbd> | Goto Type Definition (LSP) |
| <kbd>**g**</kbd> <kbd>**i**</kbd> | Goto Implementation (LSP) |
| <kbd>**g**</kbd> <kbd>**r**</kbd> | References (LSP) |
| <kbd>**g**</kbd> <kbd>**h**</kbd> | Open Call hierarchy viewer (LSP) |
| <kbd>**g**</kbd> <kbd>**H**</kbd> | Outgoing call hierarchy (LSP) |
| <kbd>**g**</kbd> <kbd>**l**</kbd> | Document Link (LSP) |
| <kbd>**g**</kbd> <kbd>**f**</kbd> | Open URI/file under cursor |
| <kbd>**Space**</kbd> <kbd>**r**</kbd> | Rename (LSP) |
| <kbd>**g**</kbd> <kbd>**L**</kbd> | Code Lens (LSP) |
| <kbd>**z**</kbd> <kbd>**o**</kbd> | Open fold |
| <kbd>**z**</kbd> <kbd>**c**</kbd> | Close fold |
| <kbd>**z**</kbd> <kbd>**a**</kbd> | Toggle fold |
| <kbd>**z**</kbd> <kbd>**R**</kbd> | Open all folds |
| <kbd>**z**</kbd> <kbd>**M**</kbd> | Close all folds |
| <kbd>**z**</kbd> <kbd>**d**</kbd> | Delete folding lines |
| <kbd>**z**</kbd> <kbd>**D**</kbd> | Delete all folding lines |
| <kbd>**Ctrl**</kbd> <kbd>**s**</kbd> | Selection Range (LSP) |
| <kbd>**Space**</kbd> <kbd>**o**</kbd> | Document Symbol (LSP) |
| <kbd>**g**</kbd> <kbd>**t**</kbd> | Switch to the next buffer |
| <kbd>**g**</kbd> <kbd>**T**</kbd> | Switch to the previous buffer |
| <kbd>**Ctrl**</kbd> <kbd>**o**</kbd> | Jump Back (Jumplist) |
| <kbd>**Ctrl**</kbd> <kbd>**i**</kbd> | Jump Forward (Jumplist) |
| <kbd>**m**</kbd> <kbd>**m**</kbd> | Toggle bookmark on current line |
| <kbd>**m**</kbd> <kbd>**n**</kbd> | Jump to next bookmark |
| <kbd>**m**</kbd> <kbd>**p**</kbd> | Jump to previous bookmark |
| <kbd>**m**</kbd> <kbd>**c**</kbd> | Clear all bookmarks in current buffer |
<!-- AUTO-GEN:end NormalMode -->

</details>

## Register

<details open>
  <summary>Register operations</summary>

<!-- AUTO-GEN:start Register -->
| Keys | Description |
|:---|:---|
| <kbd>**"**</kbd> <kbd>**Any key**</kbd> <kbd>**y**</kbd> <kbd>**y**</kbd> | Yank a line to a named register |
| <kbd>**"**</kbd> <kbd>**Any key**</kbd> <kbd>**y**</kbd> <kbd>**l**</kbd> | Yank a character to a named register |
| <kbd>**"**</kbd> <kbd>**Any key**</kbd> <kbd>**y**</kbd> <kbd>**w**</kbd> | Yank a word to a named register |
| <kbd>**"**</kbd> <kbd>**Any key**</kbd> <kbd>**y**</kbd> <kbd>**}**</kbd> | Yank to the next blank line to a named register |
| <kbd>**"**</kbd> <kbd>**Any key**</kbd> <kbd>**y**</kbd> <kbd>**{**</kbd> | Yank to the previous blank line to a named register |
| <kbd>**"**</kbd> <kbd>**Any key**</kbd> <kbd>**p**</kbd> | Paste from a named register after cursor |
| <kbd>**"**</kbd> <kbd>**Any key**</kbd> <kbd>**P**</kbd> | Paste from a named register before cursor |
| <kbd>**"**</kbd> <kbd>**Any key**</kbd> <kbd>**d**</kbd> <kbd>**d**</kbd> | Delete a line to a named register |
| <kbd>**"**</kbd> <kbd>**Any key**</kbd> <kbd>**d**</kbd> <kbd>**w**</kbd> | Delete a word to a named register |
| <kbd>**"**</kbd> <kbd>**Any key**</kbd> <kbd>**d**</kbd> <kbd>**$**</kbd> | Delete to end of line to a named register |
| <kbd>**"**</kbd> <kbd>**Any key**</kbd> <kbd>**d**</kbd> <kbd>**0**</kbd> | Delete to beginning of line to a named register |
| <kbd>**"**</kbd> <kbd>**Any key**</kbd> <kbd>**d**</kbd> <kbd>**G**</kbd> | Delete to end of file to a named register |
| <kbd>**"**</kbd> <kbd>**Any key**</kbd> <kbd>**d**</kbd> <kbd>**g**</kbd> <kbd>**g**</kbd> | Delete to beginning of file to a named register |
| <kbd>**"**</kbd> <kbd>**Any key**</kbd> <kbd>**d**</kbd> <kbd>**{**</kbd> | Delete to the previous blank line to a named register |
| <kbd>**"**</kbd> <kbd>**Any key**</kbd> <kbd>**d**</kbd> <kbd>**}**</kbd> | Delete to the next blank line to a named register |
| <kbd>**"**</kbd> <kbd>**Any key**</kbd> <kbd>**d**</kbd> <kbd>**i**</kbd> <kbd>**Any key**</kbd> | Delete inside to a named register |
| <kbd>**"**</kbd> <kbd>**Any key**</kbd> <kbd>**d**</kbd> <kbd>**h**</kbd> | Delete a character before cursor to a named register |
| <kbd>**"**</kbd> <kbd>**Any key**</kbd> <kbd>**c**</kbd> <kbd>**l**</kbd> OR <kbd>**"**</kbd> <kbd>**Any key**</kbd> <kbd>**s**</kbd> | Change a character to a named register |
| <kbd>**"**</kbd> <kbd>**Any key**</kbd> <kbd>**c**</kbd> <kbd>**i**</kbd> <kbd>**Any key**</kbd> | Change inside to a named register |
<!-- AUTO-GEN:end Register -->
 
</details>

## Visual mode

<details open>
  <summary>Visual Selection</summary>

<!-- AUTO-GEN:start VisualMode -->
| Keys | Description |
|:---|:---|
| <kbd>**d**</kbd> OR <kbd>**x**</kbd> | Delete text |
| <kbd>**c**</kbd> | Change (delete selection and enter insert mode) |
| <kbd>**y**</kbd> | Copy text |
| <kbd>**r**</kbd> | Replace character |
| <kbd>**S**</kbd> | Surround selection with character |
| <kbd>**J**</kbd> | Join lines |
| <kbd>**u**</kbd> | Convert to lowercase |
| <kbd>**U**</kbd> | Convert to uppercase |
| <kbd>**>**</kbd> | Indent |
| <kbd>**<**</kbd> | Unindent |
| <kbd>**~**</kbd> | Toggle case of character under cursor |
| <kbd>**Ctrl**</kbd> <kbd>**a**</kbd> | Increase number under cursor |
| <kbd>**Ctrl**</kbd> <kbd>**x**</kbd> | Decrease number under cursor |
| <kbd>**I**</kbd> | Insert character, multiple lines |
| <kbd>**z**</kbd> <kbd>**f**</kbd> | Fold selected lines |
| <kbd>**Ctrl**</kbd> <kbd>**s**</kbd> | Selection Range (LSP) |
| <kbd>**Esc**</kbd> | Go to Normal mode |
<!-- AUTO-GEN:end VisualMode -->

</details>

## Replace mode

<details open>
  <summary>Replace Text</summary>

<!-- AUTO-GEN:start ReplaceMode -->
| Keys | Description |
|:---|:---|
| <kbd>**Esc**</kbd> | Go to Normal mode |
| <kbd>**Backspace**</kbd> | Undo |
<!-- AUTO-GEN:end ReplaceMode -->

</details>


## Insert mode

<details open>
  <summary>Insert Text</summary>

<!-- AUTO-GEN:start InsertMode -->
| Keys | Description |
|:---|:---|
| <kbd>**Ctrl**</kbd> <kbd>**e**</kbd> | Insert the character which is below the cursor |
| <kbd>**Ctrl**</kbd> <kbd>**y**</kbd> | Insert the character which is above the cursor |
| <kbd>**Ctrl**</kbd> <kbd>**i**</kbd> | Insert a Tab |
| <kbd>**Ctrl**</kbd> <kbd>**h**</kbd> OR <kbd>**Backspace**</kbd> | Delete the character before the cursor |
| <kbd>**Ctrl**</kbd> <kbd>**t**</kbd> | Add an indent in current line |
| <kbd>**Ctrl**</kbd> <kbd>**d**</kbd> | Remove an indent in current line |
| <kbd>**Ctrl**</kbd> <kbd>**w**</kbd> | Delete the word before the cursor |
| <kbd>**Ctrl**</kbd> <kbd>**u**</kbd> | Delete all characters before the cursor in the current line |
| <kbd>**Ctrl**</kbd> <kbd>**r**</kbd> | Signature Help (LSP) |
| <kbd>**Ctrl**</kbd> <kbd>**o**</kbd> | Execute one Normal mode command and return to Insert mode |
| <kbd>**Esc**</kbd> | Go to Normal mode |
<!-- AUTO-GEN:end InsertMode -->

</details>


## Backupmanager mode

<details open>
  <summary>Backup File Manager</summary>

<!-- AUTO-GEN:start BackupManagerMode -->
| Keys | Description |
|:---|:---|
| <kbd>**j**</kbd> | Go down |
| <kbd>**k**</kbd> | Go up |
| <kbd>**g**</kbd> <kbd>**g**</kbd> | Go to the first line |
| <kbd>**G**</kbd> | Go to the last line |
| <kbd>**Enter**</kbd> | Open diff |
| <kbd>**R**</kbd> | Restore backup file |
| <kbd>**D**</kbd> | Delete backup file |
| <kbd>**r**</kbd> | Reload backup files |
<!-- AUTO-GEN:end BackupManagerMode -->

</details>


## References mode

<details open>
  <summary>References mode</summary>

<!-- AUTO-GEN:start ReferencesMode -->
| Keys | Description |
|:---|:---|
| <kbd>**j**</kbd> | Go down |
| <kbd>**k**</kbd> | Go up |
| <kbd>**g**</kbd> <kbd>**g**</kbd> | Go to the first line |
| <kbd>**G**</kbd> | Go to the last line |
| <kbd>**Enter**</kbd> | Jump to the destination |
| <kbd>**Esc**</kbd> | Quit References mode |
<!-- AUTO-GEN:end ReferencesMode -->

</details>

## Call Hierarchy mode

<details open>
  <summary>Call Hierarchy</summary>

<!-- AUTO-GEN:start CallHierarchyMode -->
| Keys | Description |
|:---|:---|
| <kbd>**j**</kbd> | Go down |
| <kbd>**k**</kbd> | Go up |
| <kbd>**g**</kbd> <kbd>**g**</kbd> | Go to the first line |
| <kbd>**G**</kbd> | Go to the last line |
| <kbd>**Enter**</kbd> | Jump to the destination |
| <kbd>**i**</kbd> | Incoming call |
| <kbd>**o**</kbd> | Outgoing call |
<!-- AUTO-GEN:end CallHierarchyMode -->

</details>

## Filer mode

<details open>
  <summary>File Manager</summary>

<!-- AUTO-GEN:start FilerMode -->
| Keys | Description |
|:---|:---|
| <kbd>**j**</kbd> | Go down |
| <kbd>**k**</kbd> | Go up |
| <kbd>**g**</kbd> <kbd>**g**</kbd> | Go to the first line |
| <kbd>**G**</kbd> | Go to the last line |
| <kbd>**l**</kbd> | Enter directory or open file |
| <kbd>**i**</kbd> | Detail Information |
| <kbd>**.**</kbd> | Toggle hidden files |
| <kbd>**D**</kbd> | Delete file |
| <kbd>**v**</kbd> | Split window and open file or directory |
| <kbd>**h**</kbd> | Split window horizontally and open file |
<!-- AUTO-GEN:end FilerMode -->

</details>


## FileTree mode

<details open>
  <summary>File Tree Sidebar</summary>

Open the fileTree sidebar with `:filetree` command. If already open, it will close and reopen.

<!-- AUTO-GEN:start FileTreeMode -->
| Keys | Description |
|:---|:---|
| <kbd>**j**</kbd> OR <kbd>**Down**</kbd> | Move selection down |
| <kbd>**k**</kbd> OR <kbd>**Up**</kbd> | Move selection up |
| <kbd>**g**</kbd> <kbd>**g**</kbd> | Move to first item |
| <kbd>**G**</kbd> | Move to last item |
| <kbd>**p**</kbd> | Move to parent node |
| <kbd>**Enter**</kbd> | Open file, or toggle expand/collapse directory |
| <kbd>**o**</kbd> | Open file, or expand directory |
| <kbd>**l**</kbd> | Open file, or expand directory |
| <kbd>**x**</kbd> | Collapse directory (or move to parent) |
| <kbd>**h**</kbd> | Collapse directory (or move to parent) |
| <kbd>**C**</kbd> | Change root to selected directory |
| <kbd>**u**</kbd> | Move root up one level |
| <kbd>**/**</kbd> | Start incremental search |
| <kbd>**n**</kbd> | Jump to next search match |
| <kbd>**N**</kbd> | Jump to previous search match |
| <kbd>**.**</kbd> | Toggle hidden files |
| <kbd>**R**</kbd> | Refresh tree |
| <kbd>**:**</kbd> | Enter command mode |
| <kbd>**Esc**</kbd> | Clear search highlight (press twice) |
| <kbd>**Ctrl**</kbd> <kbd>**w**</kbd> <kbd>**w**</kbd> | Move to next window |
| <kbd>**Ctrl**</kbd> <kbd>**w**</kbd> <kbd>**p**</kbd> | Move to previous window |
| <kbd>**Ctrl**</kbd> <kbd>**w**</kbd> <kbd>**>**</kbd> | Increase window width |
| <kbd>**Ctrl**</kbd> <kbd>**w**</kbd> <kbd>**<**</kbd> | Decrease window width |
<!-- AUTO-GEN:end FileTreeMode -->

</details>


## Buffer manager mode

<details open>
  <summary>Buffer Manager</summary>

Open the buffer manager with `:ls` command. Lists every open buffer and lets you
switch, close, or delete them.

<!-- AUTO-GEN:start BufferManagerMode -->
| Keys | Description |
|:---|:---|
| <kbd>**j**</kbd> OR <kbd>**Down**</kbd> | Go down |
| <kbd>**k**</kbd> OR <kbd>**Up**</kbd> | Go up |
| <kbd>**g**</kbd> <kbd>**g**</kbd> | Go to the first buffer |
| <kbd>**G**</kbd> | Go to the last buffer |
| <kbd>**Ctrl**</kbd> <kbd>**d**</kbd> | Half page down |
| <kbd>**Ctrl**</kbd> <kbd>**u**</kbd> | Half page up |
| <kbd>**Enter**</kbd> OR <kbd>**o**</kbd> | Open the selected buffer |
| <kbd>**D**</kbd> | Delete the selected buffer |
| <kbd>**:**</kbd> | Enter command mode |
| <kbd>**q**</kbd> OR <kbd>**Esc**</kbd> | Close Buffer Manager |
<!-- AUTO-GEN:end BufferManagerMode -->

</details>


## Bookmark manager mode

<details open>
  <summary>Bookmark Manager</summary>

Open the bookmark manager with `:bookmarks` command. Lists every bookmark
across all open buffers.

<!-- AUTO-GEN:start BookmarkManagerMode -->
| Keys | Description |
|:---|:---|
| <kbd>**j**</kbd> OR <kbd>**Down**</kbd> | Go down |
| <kbd>**k**</kbd> OR <kbd>**Up**</kbd> | Go up |
| <kbd>**g**</kbd> <kbd>**g**</kbd> | Go to the first bookmark |
| <kbd>**G**</kbd> | Go to the last bookmark |
| <kbd>**Ctrl**</kbd> <kbd>**d**</kbd> | Half page down |
| <kbd>**Ctrl**</kbd> <kbd>**u**</kbd> | Half page up |
| <kbd>**Enter**</kbd> | Jump to the selected bookmark |
| <kbd>**D**</kbd> | Delete the selected bookmark |
| <kbd>**:**</kbd> | Enter command mode |
| <kbd>**q**</kbd> OR <kbd>**Esc**</kbd> | Close Bookmark Manager |
<!-- AUTO-GEN:end BookmarkManagerMode -->

</details>


## Document symbol mode

<details open>
  <summary>Document Symbol Viewer</summary>

Open the document symbol viewer with <kbd>**Space**</kbd> <kbd>**o**</kbd> in
Normal mode. Lists the symbols (functions, classes, variables, ...) reported
by the active LSP server for the current buffer.

<!-- AUTO-GEN:start DocumentSymbolMode -->
| Keys | Description |
|:---|:---|
| <kbd>**j**</kbd> OR <kbd>**Down**</kbd> | Go down |
| <kbd>**k**</kbd> OR <kbd>**Up**</kbd> | Go up |
| <kbd>**g**</kbd> <kbd>**g**</kbd> | Go to the first symbol |
| <kbd>**G**</kbd> | Go to the last symbol |
| <kbd>**Ctrl**</kbd> <kbd>**d**</kbd> | Half page down |
| <kbd>**Ctrl**</kbd> <kbd>**u**</kbd> | Half page up |
| <kbd>**Enter**</kbd> | Jump to the selected symbol |
| <kbd>**:**</kbd> | Enter command mode |
| <kbd>**q**</kbd> OR <kbd>**Esc**</kbd> | Close Document Symbol viewer |
<!-- AUTO-GEN:end DocumentSymbolMode -->

</details>


## Log viewer mode

<details open>
  <summary>Log Viewer</summary>

Open the log viewer with `:log` (editor log) or `:lsplog` (LSP log). The
viewer renders the log as a read-only buffer and supports the usual Vim-style
motions and searches.

<!-- AUTO-GEN:start LogViewerMode -->
| Keys | Description |
|:---|:---|
| <kbd>**h**</kbd> OR <kbd>**Left**</kbd> | Go left |
| <kbd>**j**</kbd> OR <kbd>**Down**</kbd> | Go down |
| <kbd>**k**</kbd> OR <kbd>**Up**</kbd> | Go up |
| <kbd>**l**</kbd> OR <kbd>**Right**</kbd> | Go right |
| <kbd>**0**</kbd> OR <kbd>**Home**</kbd> | Go to the first character of the line |
| <kbd>**$**</kbd> OR <kbd>**End**</kbd> | Go to the end of the line |
| <kbd>**w**</kbd> | Go forwards to the start of a word |
| <kbd>**b**</kbd> | Go backwards to the start of a word |
| <kbd>**e**</kbd> | Go forwards to the end of a word |
| <kbd>**{**</kbd> | Go to the previous blank line |
| <kbd>**}**</kbd> | Go to the next blank line |
| <kbd>**g**</kbd> <kbd>**g**</kbd> | Go to the first line |
| <kbd>**G**</kbd> | Go to the last line |
| <kbd>**Ctrl**</kbd> <kbd>**d**</kbd> | Half page down |
| <kbd>**Ctrl**</kbd> <kbd>**u**</kbd> | Half page up |
| <kbd>**Ctrl**</kbd> <kbd>**f**</kbd> | Page down |
| <kbd>**Ctrl**</kbd> <kbd>**b**</kbd> | Page up |
| <kbd>**/**</kbd> | Search forwards |
| <kbd>**?**</kbd> | Search backwards |
| <kbd>**n**</kbd> | Repeat last search forwards |
| <kbd>**N**</kbd> | Repeat last search backwards |
| <kbd>*****</kbd> | Search forwards for the word under cursor |
| <kbd>**#**</kbd> | Search backwards for the word under cursor |
| <kbd>**v**</kbd> | Start character-wise Visual selection |
| <kbd>**V**</kbd> | Start line-wise Visual selection |
| <kbd>**Ctrl**</kbd> <kbd>**v**</kbd> | Start block-wise Visual selection |
| <kbd>**r**</kbd> | Refresh log content |
| <kbd>**:**</kbd> | Enter command mode |
| <kbd>**q**</kbd> | Close Log Viewer |
<!-- AUTO-GEN:end LogViewerMode -->

</details>


## Recent file mode

<details open>
  <summary>Recent File Selector</summary>

Open the recent file selector with `:recent` (Linux only). Lists the files
recorded by the desktop `recently-used.xbel` database.

<!-- AUTO-GEN:start RecentFileMode -->
| Keys | Description |
|:---|:---|
| <kbd>**j**</kbd> OR <kbd>**Down**</kbd> | Move selection down |
| <kbd>**k**</kbd> OR <kbd>**Up**</kbd> | Move selection up |
| <kbd>**g**</kbd> <kbd>**g**</kbd> | Move to the first file |
| <kbd>**G**</kbd> | Move to the last file |
| <kbd>**Ctrl**</kbd> <kbd>**d**</kbd> | Half page down |
| <kbd>**Ctrl**</kbd> <kbd>**u**</kbd> | Half page up |
| <kbd>**Enter**</kbd> | Open the selected file |
| <kbd>**:**</kbd> | Enter command mode |
<!-- AUTO-GEN:end RecentFileMode -->

</details>


## Debug mode

<details open>
  <summary>Debug Viewer</summary>

Open the debug viewer with `:debug`. Shows internal editor state for
troubleshooting; the viewer is read-only.

<!-- AUTO-GEN:start DebugMode -->
| Keys | Description |
|:---|:---|
| <kbd>**j**</kbd> OR <kbd>**Down**</kbd> | Scroll down |
| <kbd>**k**</kbd> OR <kbd>**Up**</kbd> | Scroll up |
| <kbd>**g**</kbd> OR <kbd>**Home**</kbd> | Go to top |
| <kbd>**G**</kbd> OR <kbd>**End**</kbd> | Go to bottom |
| <kbd>**Ctrl**</kbd> <kbd>**d**</kbd> OR <kbd>**Page Down**</kbd> | Page down |
| <kbd>**Ctrl**</kbd> <kbd>**u**</kbd> OR <kbd>**Page Up**</kbd> | Page up |
| <kbd>**q**</kbd> | Close the debug viewer |
| <kbd>**:**</kbd> | Enter command mode |
<!-- AUTO-GEN:end DebugMode -->

</details>


## Terminal mode

<details open>
  <summary>Built-in Terminal Emulator</summary>

### Terminal-Input sub-mode (default)

All keystrokes are forwarded to the running shell/command.

<!-- AUTO-GEN:start TerminalInput -->
| Keys | Description |
|:---|:---|
| <kbd>**Ctrl**</kbd> <kbd>**\\**</kbd> <kbd>**Ctrl**</kbd> <kbd>**n**</kbd> | Switch to Terminal-Normal sub-mode |
<!-- AUTO-GEN:end TerminalInput -->

### Terminal-Normal sub-mode

<!-- AUTO-GEN:start TerminalNormal -->
| Keys | Description |
|:---|:---|
| <kbd>**i**</kbd> | Return to Terminal-Input sub-mode |
| <kbd>**a**</kbd> | Return to Terminal-Input sub-mode |
| <kbd>**:**</kbd> | Enter command mode |
<!-- AUTO-GEN:end TerminalNormal -->

</details>

## Configuration mode

<details open>
  <summary>Configuration mode</summary>

Open the configuration viewer with `:config`. Lets you browse and edit the
current settings interactively; press <kbd>**Enter**</kbd> (or
<kbd>**l**</kbd> / <kbd>**Space**</kbd>) on the selected row to toggle a
bool, open the enum popup, or start editing an int/float/string/color.

<!-- AUTO-GEN:start ConfigMode -->
| Keys | Description |
|:---|:---|
| <kbd>**j**</kbd> OR <kbd>**Down**</kbd> | Move selection down |
| <kbd>**k**</kbd> OR <kbd>**Up**</kbd> | Move selection up |
| <kbd>**g**</kbd> <kbd>**g**</kbd> | Go to the first item |
| <kbd>**G**</kbd> | Go to the last item |
| <kbd>**Ctrl**</kbd> <kbd>**d**</kbd> | Half page down |
| <kbd>**Ctrl**</kbd> <kbd>**u**</kbd> | Half page up |
| <kbd>**Enter**</kbd> | Toggle bool, open enum popup, or start editing int/float/string/color |
| <kbd>**l**</kbd> OR <kbd>**Space**</kbd> | Same as Enter |
| <kbd>**Right**</kbd> | Cycle enum forward, increment int/float, or toggle bool |
| <kbd>**Left**</kbd> | Cycle enum backward, or decrement int/float |
| <kbd>**h**</kbd> | Cycle enum backward, or decrement int/float |
| <kbd>**/**</kbd> | Search forwards |
| <kbd>**?**</kbd> | Search backwards |
| <kbd>**n**</kbd> | Jump to next search match |
| <kbd>**N**</kbd> | Jump to previous search match |
| <kbd>**:**</kbd> | Enter command mode |
| <kbd>**Esc**</kbd> | Clear search highlight (press twice) |
<!-- AUTO-GEN:end ConfigMode -->

</details>

## Command mode

<details open>
  <summary>Command mode</summary>

<!-- AUTO-GEN:start CommandMode -->
| Command | Description |
|:---|:---|
| `number` | Jump to line number; e.g. `:10` |
| `! shell command` | Shell command execution |
| `bg` | Pause the editor and show the recent terminal output |
| `man arguments` | Show the given UNIX manual page, if available; e.g. `:man man` |
| `e filename` | Open file |
| `e` | Reload current file (error if unsaved changes) |
| `e!` | Force reload current file (discard unsaved changes) |
| `e! filename` | Open file (discard unsaved changes) |
| `ene` | Create a new empty buffer |
| `new` | Create a new empty buffer in a horizontally split window |
| `vnew` | Create a new empty buffer in a vertically split window |
| `delete` | Delete current line and copy to register |
| `ls` | Display all buffers |
| `bprev` | Switch to the previous buffer |
| `bnext` | Switch to the next buffer |
| `bfirst` | Switch to the first buffer |
| `blast` | Switch to the last buffer |
| `bd` or `bd number` | Delete buffer |
| `vs` | Vertical split window |
| `vs filename` | Open in a vertical split window |
| `sp` | Horizontal split window |
| `sp filename` | Open in a horizontal split window |
| `only` | Close all other windows |
| `theme themeName` | Change color theme; e.g. `theme dark` |
| `noh` | Turn off search highlights |
| `stripwhitespace` | Delete trailing spaces |
| `%s/keyword1/keyword2/` | Replace text (normal mode only) |
| `%d` | Delete all lines and copy to register |
| `1,10d` | Delete lines in range and copy to register |
| `set number` or `set nonumber` | Show/hide line numbers (alias: `nu`, `nonu`) |
| `set relativenumber` or `set norelativenumber` | Show/hide relative line numbers (alias: `rnu`, `nornu`) |
| `set cursorline` or `set nocursorline` | Highlight the current line (alias: `cul`, `nocul`) |
| `set cursorcolumn` or `set nocursorcolumn` | Highlight the current column (alias: `cuc`, `nocuc`) |
| `set statusline` or `set nostatusline` | Show/hide status line (alias: `stl`, `nostl`) |
| `set syntax` or `set nosyntax` | Enable/disable syntax highlighting (alias: `syn`, `nosyn`) |
| `set indentationlines` or `set noindentationlines` | Enable/disable indentation guide lines (alias: `indl`, `noindl`) |
| `set autoindent` or `set noautoindent` | Enable/disable auto indent (alias: `ai`, `noai`) |
| `set autocloseparen` or `set noautocloseparen` | Enable/disable auto close paren (alias: `acp`, `noacp`) |
| `set autodeleteparen` or `set noautodeleteparen` | Enable/disable auto delete paren (alias: `adp`, `noadp`) |
| `set clipboard` or `set noclipboard` | Enable/disable system clipboard (alias: `cb`, `nocb`) |
| `set smoothscroll` or `set nosmoothscroll` | Enable/disable smooth scroll (alias: `sms`, `nosms`) |
| `set livereload` or `set nolivereload` | Enable/disable live reload of config (alias: `lr`, `nolr`) |
| `set icon` or `set noicon` | Show/hide icons in filer mode (alias: `icons`, `noicons`) |
| `set highlightcurrentline` or `set nohighlightcurrentline` | Highlight the current line (alias: `hcl`, `nohcl`) |
| `set highlightcurrentword` or `set nohighlightcurrentword` | Highlight other uses of the current word (alias: `hcw`, `nohcw`) |
| `set highlightfullspace` or `set nohighlightfullspace` | Highlight full width space (alias: `hfs`, `nohfs`) |
| `set highlightparen` or `set nohighlightparen` | Highlight matching paren (alias: `hp`, `nohp`) |
| `set highlightfindchar` or `set nohighlightfindchar` | Highlight f/F/t/T matches (alias: `hfc`, `nohfc`) |
| `set highlightcolorcode` or `set nohighlightcolorcode` | Highlight inline color codes (`#RRGGBB`, `#RGB`) with their actual color (alias: `hcc`, `nohcc`) |
| `set highlightgitconflict` or `set nohighlightgitconflict` | Highlight git merge conflict blocks (`<<<<<<<` / `=======` / `>>>>>>>`) (alias: `hgc`, `nohgc`) |
| `set highlightgitconflicttwocolor` or `set nohighlightgitconflicttwocolor` | Use two-color (ours/theirs) conflict scheme; disable for single-color fallback (alias: `hgctc`, `nohgctc`) |
| `set multistatusline` or `set nomultistatusline` | Enable/disable multiple status line (alias: `msl`, `nomsl`) |
| `set ignorecase` or `set noignorecase` | Enable/disable ignorecase (alias: `ic`, `noic`) |
| `set smartcase` or `set nosmartcase` | Enable/disable smartcase (alias: `scs`, `noscs`) |
| `set incsearch` or `set noincsearch` | Enable/disable incremental search (alias: `is`, `nois`) |
| `set hlsearch` or `set nohlsearch` | Enable/disable search highlighting (alias: `hls`, `nohls`) |
| `set buildonsave` or `set nobuildonsave` | Enable/disable build on save (alias: `bos`, `nobos`) |
| `set showgitinactive` or `set noshowgitinactive` | Show/hide git branch in inactive window (alias: `sgi`, `nosgi`) |
| `set wrap` or `set nowrap` | Enable/disable line wrap |
| `set expandtab` or `set noexpandtab` | Enable/disable expand tab to spaces (alias: `et`, `noet`) |
| `set scrollbar` or `set noscrollbar` | Enable/disable scrollbar |
| `set scrollbarwidth=number` | Change scrollbar width (0 = hidden); e.g. `set scrollbarwidth=1` |
| `set tabstop=number` | Change tab stop width; e.g. `set tabstop=4` (alias: `ts`) |
| `set shiftwidth=number` | Change indent width; e.g. `set shiftwidth=4` (alias: `sw`) |
| `set softtabstop=number` | Change soft tab stop width; e.g. `set softtabstop=4` (alias: `sts`) |
| `set scrollfriction=number` | Change smooth scroll friction; e.g. `set scrollfriction=80.0` (alias: `sfr`) |
| `set scrollairdrag=number` | Change smooth scroll air drag; e.g. `set scrollairdrag=2.0` (alias: `sad`) |
| `build` | Build the current buffer |
| `lspfold` | LSP Folding Range |
| `lspformat` | LSP Document Formatting |
| `log` | Open a log viewer for editor log |
| `lsplog` | Open a log viewer for LSP log |
| `lsprestart` | Restart the current LSP server |
| `lspcallhierarchyincoming` | Show incoming calls (callers) at cursor |
| `lspcallhierarchyoutgoing` | Show outgoing calls (callees) at cursor |
| `help` | Open this help |
| `putconfigfile` | Put a sample configuration file in ~/.config/moe |
| `moerc` | Open the configuration file (moerc.toml) for editing |
| `quickrun` | Quick run |
| `recent` | Open recent file selection mode (Only supported on Linux) |
| `backup` | Open backup file manager |
| `config` | Open configuration mode |
| `debug` | Open debug mode |
| `filetree` | Toggle FileTree sidebar |
| `filetree path` | Toggle FileTree sidebar with specified root path |
| `jump` | Open Jump list viewer |
| `terminal` | Open terminal emulator (default shell) |
| `terminal command` | Run command in terminal emulator |
| `changes` | Show Change list |
| `bookmarks` | Show bookmark list |
| `conflictnext` | Jump to next git merge conflict block |
| `conflictprev` | Jump to previous git merge conflict block |
<!-- AUTO-GEN:end CommandMode -->

</details>

### Runtime Key Mapping

<details open>
  <summary>Runtime key mapping commands</summary>

Map, unmap, and clear runtime key mappings. The `:map`-family commands expand the
right-hand side recursively (a remapped key on the RHS is itself re-expanded),
while the `:noremap`-family commands map keys verbatim (non-recursive). Unmapping
with `:unmap` or clearing with `:mapclear` restores the built-in default for the
affected keys.
Mappings are session-only and not persisted across restarts.
For persistent key mappings, use the `[KeyMapping]` section in `moerc.toml`. See [configfile.md](configfile.md#keymapping-table).

<!-- AUTO-GEN:start RuntimeKeyMap -->
| Command | Description |
|:---|:---|
| `nmap {lhs} {rhs}` | Map keys (Normal mode) |
| `nmap` | List all Normal mode mappings |
| `imap {lhs} {rhs}` | Map keys (Insert mode) |
| `imap` | List all Insert mode mappings |
| `vmap {lhs} {rhs}` | Map keys (Visual modes) |
| `vmap` | List all Visual mode mappings |
| `rmap {lhs} {rhs}` | Map keys (Replace mode) |
| `rmap` | List all Replace mode mappings |
| `cmap {lhs} {rhs}` | Map keys (Command mode) |
| `cmap` | List all Command mode mappings |
| `map {lhs} {rhs}` | Map keys (all modes) |
| `map` | List all mode mappings |
| `nunmap {lhs}` | Unmap keys (Normal mode) |
| `iunmap {lhs}` | Unmap keys (Insert mode) |
| `vunmap {lhs}` | Unmap keys (Visual modes) |
| `runmap {lhs}` | Unmap keys (Replace mode) |
| `cunmap {lhs}` | Unmap keys (Command mode) |
| `unmap {lhs}` | Unmap keys (all modes) |
| `nmapclear` | Clear mappings (Normal mode) |
| `imapclear` | Clear mappings (Insert mode) |
| `vmapclear` | Clear mappings (Visual modes) |
| `rmapclear` | Clear mappings (Replace mode) |
| `cmapclear` | Clear mappings (Command mode) |
| `mapclear` | Clear mappings (all modes) |
<!-- AUTO-GEN:end RuntimeKeyMap -->

`noremap`, `nnoremap`, `inoremap`, `vnoremap`, `cnoremap` map keys non-recursively
(the right-hand side is replayed verbatim, like Vim's `noremap`).

**Key notation:**

| Notation | Meaning |
|:---|:---|
| `a`, `j`, `0` | Regular keys |
| `C-s`, `M-x` | Modifier keys (`C`=Ctrl, `M`=Alt, `S`=Shift) |
| `Escape`, `Enter`, `Tab` | Special keys |
| `Up`, `Down`, `F1`-`F12` | Arrow and function keys |
| `Space` | Space key |
| `j j`, `g g` | Multi-key sequences (space-separated) |
| `jj`, `gg` | Vim-style concatenated keys (equivalent to `j j`, `g g`) |

The `{rhs}` can take any of these forms:

| RHS form | Meaning |
|:---|:---|
| `<command>` | A registered command name (e.g. `save-and-quit`) |
| `<command> <args...>` | A registered command with arguments |
| `<keys>` | A key sequence replayed as input (e.g. `Escape`, `g g`) |
| `mode_switch <mode>` | Switch to a mode (`normal`, `insert`, `visual`, `replace`, `command`) |
| `overlay_switch <overlay>` | Open an overlay (`command`, `search`, `rename`) |

`mode_switch` and `overlay_switch` are reserved first words. The same RHS forms
work in the `[KeyMapping]` config section.

**Examples:**

```
:nmap C-s save-and-quit       " Ctrl-S saves and quits (Normal mode)
:imap jj Escape               " jj exits Insert mode
:nmap C-a g g                 " Ctrl-A goes to first line
:vmap C-c Escape              " Ctrl-C exits Visual mode
:cmap C-a Home                " Ctrl-A moves to line start (Command mode)
:nmap C-e mode_switch insert  " Ctrl-E enters Insert mode
:nmap C-p overlay_switch command  " Ctrl-P opens the command line
:nmap                         " List all Normal mode mappings
:map                          " List all mode mappings
:nunmap C-s                   " Remove Ctrl-S mapping in Normal mode
:nmapclear                    " Clear all Normal mode runtime mappings
```

</details>

[Go To Top](#table-of-contents)
