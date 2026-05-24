# Configuration file

Write moe's configuration file in toml.  
The location is

```
~/.config/moe/moerc.toml
```

You can use the example -> https://github.com/fox0430/moe/blob/develop/example

## Configuration Items

### CursorType

- type: string

| Name |
|:-----------------------------|
| terminalDefault |
| blinkBlock |
| blinkIbeam |
| nonBlinkBlock |
| nonBlinkIbeam |


### ColorMode

- type: string

| Name |
|:-----------------------------|
| none |
| 8 |
| 16 |
| 256 |
| 24bit |


### ClipboardTool

- type: string

| Name |
|:-----------------------------|
| xsel |
| xclip |
| wl-clipboard |
| win32yank |
| pbcopy |


### StatusLineItem

- type: string

| Name |
|:-----------------------------|
| lineNumber |
| totalLines |
| columnNumber |
| totalColumns |
| encoding |
| lineEnding |
| fileType |
| fileTypeIcon |


### BufferBackend

- type: string

| Name | Description |
|:-----------------------------|:-----------------------------|
| auto | Pick a backend based on the file size (default) |
| gapBuffer | GapBuffer |
| sqrtDecomp | Sqrt Decomposition |
| rope | Rope (B-tree) |
| pieceTable | Piece Table (Red-Black Tree) |


### ThemeKind

- type: string

| Name | Description |
|:-----------------------------|:-----------------------------|
| default | The default theme |
| vscode | VSCode theme |
| config | User theme. Also please set `Theme.path` |

### Standard table

<!-- AUTO-GEN:start Standard -->
| Name | Type | Default Value | Description |
|:---|:---|:---|:---|
| number | bool | true | Display line numbers |
| relativeNumber | bool | false | Display relative line numbers |
| statusLine | bool | true | Display status lines |
| syntax | bool | true | Enable syntax highlighting |
| indentationLines | bool | true | Enable indentation lines |
| tabStop | integer | 2 | Tab width |
| shiftWidth | integer | 0 | Indent width (0 = use tabStop) |
| softTabStop | integer | 0 | Tab/Backspace width in insert mode (0 = use tabStop) |
| expandTab | bool | false | Expand tabs to spaces |
| sidebar | bool | true | Enable Sidebars for editor views |
| scrollbar | bool | false | Enable scrollbar on the right edge of windows |
| scrollbarWidth | integer | 1 | Scrollbar width in characters (0 = hidden) |
| bookmarkMarker | string | "♥ " | Bookmark indicator symbol in sidebars |
| showModifiedLines | bool | true | Show modified/inserted line indicators in sidebars |
| autoCloseParen | bool | true | Automatic closing brackets |
| autoIndent | bool | true | Automatic indentation |
| smartIndent | bool | false | Language-aware extra indent on Enter (Nim: var/let/const/type, trailing or/and/object/tuple/enum, trailing `:` or `=`, unclosed brackets) |
| ignorecase | bool | true | Enable ignorecase when searching |
| smartcase | bool | true | Enable smartcase when searching |
| disableChangeCursor | bool | false | Disable change of the cursor shape |
| defaultCursor | string (enum: terminalDefault, blinkBlock, blinkIbeam, nonBlinkBlock, nonBlinkIbeam) | terminalDefault | The cursor shape of the terminal emulator you are using |
| normalModeCursor | string (enum: terminalDefault, blinkBlock, blinkIbeam, nonBlinkBlock, nonBlinkIbeam) | blinkBlock | The cursor shape in Normal mode |
| insertModeCursor | string (enum: terminalDefault, blinkBlock, blinkIbeam, nonBlinkBlock, nonBlinkIbeam) | blinkIbeam | The cursor shape in insert mode |
| liveReloadOfConf | bool | false | Enable live reload of the configuration file |
| incrementalSearch | bool | true | Enable incremental search |
| popupWindowInExmode | bool | true | Show Pop-up window in Command mode |
| autoDeleteParen | bool | true | Automatic delete brackets |
| liveReloadOfFile | bool | true | Enable live reload of opening files |
| colorMode | string (enum: 8, 16, 256, 24bit, none) | 256 | Terminal color mode |
| mouse | bool | false | Enable mouse cursor movement |
| lineWrap | bool | true | Enable line wrapping |
| timeoutlen | integer | 1000 | Key mapping timeout in milliseconds (0 = no timeout) |
| bufferBackend | string (enum: auto, gapBuffer, sqrtDecomp, rope, pieceTable) | auto | Buffer data structure. "auto" selects backend based on file size |
| bracketSplit | string (enum: disable, noIndent, indent) | disable | Behavior when pressing Enter between matching bracket pairs (disable/noIndent/indent) |
<!-- AUTO-GEN:end Standard -->


### Clipboard table

<!-- AUTO-GEN:start Clipboard -->
| Name | Type | Default Value | Description |
|:---|:---|:---|:---|
| enable | bool | true | Enable system clipboard |
| tool | string (enum: xsel, xclip, wl-clipboard, win32yank, pbcopy) | xsel | The clipboard tool for Linux |
<!-- AUTO-GEN:end Clipboard -->


### TabLine table

<!-- AUTO-GEN:start TabLine -->
| Name | Type | Default Value | Description |
|:---|:---|:---|:---|
| enable | bool | true | Enable tab line |
<!-- AUTO-GEN:end TabLine -->


### StatusLine table

<!-- AUTO-GEN:start StatusLine -->
| Name | Type | Default Value | Description |
|:---|:---|:---|:---|
| multipleStatusLine | bool | true | Show multiple status lines |
| merge | bool | false | Enable merge the status line with the command line |
| mode | bool | true | Display the current mode |
| filename | bool | true | Display the filename |
| changedMark | bool | true | Display the buffer changed mark |
| directory | bool | true | Display the directory of the path |
| gitChangedLines | bool | true | Display number of changed lines |
| gitBranchName | bool | true | Display the current git branch name |
| showGitInactive | bool | false | Display the git branch name on the status line in inactive windows |
| showModeInactive | bool | false | Display the mode on the status line in inactive windows |
| setupText | string | "{lineNumber}/{totalLines} {columnNumber}/{totalColumns} {encoding} {lineEnding} {fileType}" | Text to customize the items displayed in the status line. Please check StatusLineItem |
<!-- AUTO-GEN:end StatusLine -->


### BuildOnSave table

<!-- AUTO-GEN:start BuildOnSave -->
| Name | Type | Default Value | Description |
|:---|:---|:---|:---|
| enable | bool | false | Enable build on save |
| workspaceRoot | string (optional) | none | Project root directory |
| command | string (optional) | none | Override commands executed at build |
<!-- AUTO-GEN:end BuildOnSave -->


### Highlight table

<!-- AUTO-GEN:start Highlight -->
| Name | Type | Default Value | Description |
|:---|:---|:---|:---|
| currentLine | bool | true | Highlight the current line background |
| currentColumn | bool | false | Highlight the current column background |
| reservedWord | string array | ["TODO", "WIP", "NOTE"] | Highlight any words |
| replaceText | bool | true | Highlight replacement text |
| pairOfParen | bool | true | Highlight a pair of brackets |
| fullWidthSpace | bool | true | Highlight full-width spaces |
| trailingSpaces | bool | true | Highlight trailing spaces |
| currentWord | bool | true | Highlight other uses of the current word under the cursor |
| findCharHighlight | bool | true | Highlight f/F/t/T matches |
| colorCodeHighlight | bool | true | Highlight inline color codes (#RRGGBB, #RGB) with their actual color |
| gitConflict | bool | true | Highlight git merge conflict blocks (`<<<<<<<` / `=======` / `>>>>>>>`) |
| gitConflictTwoColor | bool | true | Use GitHub-style two-color scheme (ours / theirs distinct); false for single red background |
<!-- AUTO-GEN:end Highlight -->


### AutoBackup table

<!-- AUTO-GEN:start AutoBackup -->
| Name | Type | Default Value | Description |
|:---|:---|:---|:---|
| enable | bool | false | Enable automatic backups |
| backupDir | string (optional) | "~/.cache/moe/backups" | Directory to save backup files |
| idleTime | integer | 10 | Start backup when there is no operation times (seconds) |
| interval | integer | 5 | Backup interval (minutes) |
| dirToExclude | string array | ["/etc"] | Exclude dirs for where you don't want to produce automatic backups |
<!-- AUTO-GEN:end AutoBackup -->


### QuickRun table

<!-- AUTO-GEN:start QuickRun -->
| Name | Type | Default Value | Description |
|:---|:---|:---|:---|
| saveBufferWhenQuickRun | bool | true | Save buffer when run QuickRun |
| command | string (optional) | none | Commands to be executed by quick run |
| timeout | integer | 30 | Command timeout (seconds) |
| nimAdvancedCommand | string (optional) | none | Nim compiler advanced args |
| clangOptions | string (optional) | none | C lang compiler options. The default compiler is gcc |
| cppOptions | string (optional) | none | C++ compiler options. The default compiler is gcc |
| nimOptions | string (optional) | none | Nim compiler options |
| shOptions | string (optional) | none | sh options |
| bashOptions | string (optional) | none | bash options |
<!-- AUTO-GEN:end QuickRun -->


### Notification table

<!-- AUTO-GEN:start Notification -->
| Name | Type | Default Value | Description |
|:---|:---|:---|:---|
| screenNotifications | bool | true | Show all messages/notifications in the command line |
| logNotifications | bool | true | Record all messages/notifications to the log |
| autoBackupScreenNotify | bool | true | Auto backups messages/notifications in the command line |
| autoBackupLogNotify | bool | true | Auto backups messages/notifications to the log |
| autoSaveScreenNotify | bool | true | Auto save messages/notifications in the command line |
| autoSaveLogNotify | bool | true | Auto save messages/notifications to the log |
| yankScreenNotify | bool | true | Yank messages/notifications in the command line |
| yankLogNotify | bool | true | Yank messages/notifications to the log |
| deleteScreenNotify | bool | true | Delete buffer messages/notifications in the command line |
| deleteLogNotify | bool | true | Delete buffer messages/notifications to the log |
| saveScreenNotify | bool | true | Save messages/notifications in the command line |
| saveLogNotify | bool | true | Save messages/notifications to the log |
| quickRunScreenNotify | bool | true | QuickRun messages/notifications in the command line |
| quickRunLogNotify | bool | true | QuickRun messages/notifications to the log |
| buildOnSaveScreenNotify | bool | true | Build on save messages/notifications in the command line |
| buildOnSaveLogNotify | bool | true | Build on save messages/notifications to the log |
| filerScreenNotify | bool | true | Filer messages/notifications in the command line |
| filerLogNotify | bool | true | Filer messages/notifications to the log |
| restoreScreenNotify | bool | true | Restore messages/notifications in the command line |
| restoreLogNotify | bool | true | Restore messages/notifications to the log |
| lspScreenNotify | bool | true | Lsp messages/notifications in the command line |
| lspLogNotify | bool | true | Lsp messages/notifications to the log |
| lspForcePopup | bool | true | Force all LSP messages (including logs) to popup notifications |
| popupNotifications | bool | false | Show notifications as floating popups instead of the command line |
| popupPosition | string | "bottomRight" | Popup position: "topRight", "topLeft", "bottomRight", "bottomLeft" |
| popupTimeoutMs | integer | 3000 | Auto-dismiss timeout in milliseconds (minimum: 100) |
| popupMaxVisible | integer | 3 | Maximum number of simultaneous popup notifications (minimum: 1) |
| popupMaxWidth | integer | 60 | Maximum popup width in characters (minimum: 10) |
| popupBorder | bool | false | Show border around popup notifications |
<!-- AUTO-GEN:end Notification -->


### Filer table

<!-- AUTO-GEN:start Filer -->
| Name | Type | Default Value | Description |
|:---|:---|:---|:---|
| showIcons | bool | true | Show/Hidden file type icons |
<!-- AUTO-GEN:end Filer -->


### Autocomplete table

<!-- AUTO-GEN:start Autocomplete -->
| Name | Type | Default Value | Description |
|:---|:---|:---|:---|
| enable | bool | true | Enable/Disable General-purpose autocompletion |
| windowBorder | bool | true | Show borderline on completion window |
<!-- AUTO-GEN:end Autocomplete -->


### AutoSave table

<!-- AUTO-GEN:start AutoSave -->
| Name | Type | Default Value | Description |
|:---|:---|:---|:---|
| enable | bool | true | Auto save |
| interval | integer | 5 | Auto save interval (minutes) |
<!-- AUTO-GEN:end AutoSave -->


### Persist table

<!-- AUTO-GEN:start Persist -->
| Name | Type | Default Value | Description |
|:---|:---|:---|:---|
| commandHistory | bool | true | Saving Command mode command history |
| commandHistoryLimit | integer | 1000 | The maximum entries of Command mode command history to save |
| search | bool | true | Saving search history |
| searchHistoryLimit | integer | 1000 | The maximum entries of search history to save |
| cursorPosition | bool | true | Saving last cursor position |
| bookmarks | bool | true | Saving bookmarks |
<!-- AUTO-GEN:end Persist -->


### Log table

<!-- AUTO-GEN:start Log -->
| Name | Type | Default Value | Description |
|:---|:---|:---|:---|
| clearOnStart | bool | false | Clear existing log file when starting with debug mode |
<!-- AUTO-GEN:end Log -->


### Debug.WindowNode table

<!-- AUTO-GEN:start Debug.WindowNode -->
| Name | Type | Default Value | Description |
|:---|:---|:---|:---|
| enable | bool | true | All WindowNode info |
| currentWindow | bool | true | Whether the current window or not |
| index | bool | true | WindowNode.index |
| windowIndex | bool | true | WindowNode.windowIndex |
| bufferIndex | bool | true | WindowNode.bufferIndex |
| parentIndex | bool | true | Parent node's WindowNode.index |
| childLen | bool | true | WindowNode.child.len |
| splitType | bool | true | WindowNode.splitType |
| haveCursesWin | bool | true | Whether windowNode have cursesWindow or not |
| y | bool | true | WindowNode.y |
| x | bool | true | WindowNode.x |
| h | bool | true | WindowNode.h |
| w | bool | true | WindowNode.w |
| currentLine | bool | true | WindowNode.currentLine |
| currentColumn | bool | true | WindowNode.currentColumn |
| expandedColumn | bool | true | WindowNode.expandedColumn |
| cursor | bool | true | WindowNode.cursor |
<!-- AUTO-GEN:end Debug.WindowNode -->


### Debug.EditorView table

<!-- AUTO-GEN:start Debug.EditorView -->
| Name | Type | Default Value | Description |
|:---|:---|:---|:---|
| enable | bool | true | All Editorview info |
| widthOfLineNum | bool | true | Editorview.widthOfLineNum |
| height | bool | true | Editorview.height |
| width | bool | true | Editorview.width |
| originalLine | bool | false | Editorview.originalLine |
| start | bool | false | Editorview.start |
| length | bool | false | Editorview.length |
<!-- AUTO-GEN:end Debug.EditorView -->


### Debug.BufferStatus table

<!-- AUTO-GEN:start Debug.BufferStatus -->
| Name | Type | Default Value | Description |
|:---|:---|:---|:---|
| enable | bool | true | All BufStatus info |
| bufferIndex | bool | true | The index of BufStatus |
| path | bool | true | BufStatus.path |
| openDir | bool | true | BufStatus.openDir |
| currentMode | bool | true | BufStatus.mode |
| prevMode | bool | true | BufStatus.prevMode |
| language | bool | true | BufStatus.language |
| encoding | bool | true | BufStatus.characterEncoding |
| countChange | bool | true | BufStatus.countChange |
| cmdLoop | bool | true | BufStatus.cmdLoop |
| lastSaveTime | bool | true | BufStatus.lastSaveTime |
| bufferLen | bool | true | BufStatus.buffer.len |
<!-- AUTO-GEN:end Debug.BufferStatus -->


### Debug.Search table

<!-- AUTO-GEN:start Debug.Search -->
| Name | Type | Default Value | Description |
|:---|:---|:---|:---|
| enable | bool | true | Search debug info |
<!-- AUTO-GEN:end Debug.Search -->


### Debug.MacroState table

<!-- AUTO-GEN:start Debug.MacroState -->
| Name | Type | Default Value | Description |
|:---|:---|:---|:---|
| enable | bool | true | Macro state debug info |
<!-- AUTO-GEN:end Debug.MacroState -->


### Debug.Visual table

<!-- AUTO-GEN:start Debug.Visual -->
| Name | Type | Default Value | Description |
|:---|:---|:---|:---|
| enable | bool | true | Visual selection debug info |
<!-- AUTO-GEN:end Debug.Visual -->


### Debug.JumpList table

<!-- AUTO-GEN:start Debug.JumpList -->
| Name | Type | Default Value | Description |
|:---|:---|:---|:---|
| enable | bool | true | Jump list debug info |
<!-- AUTO-GEN:end Debug.JumpList -->


### Debug.Lsp table

<!-- AUTO-GEN:start Debug.Lsp -->
| Name | Type | Default Value | Description |
|:---|:---|:---|:---|
| enable | bool | true | LSP debug info |
<!-- AUTO-GEN:end Debug.Lsp -->


### Git table

<!-- AUTO-GEN:start Git -->
| Name | Type | Default Value | Description |
|:---|:---|:---|:---|
| showChangedLine | bool | true | Line changes on sidebars |
| updateInterval | integer | 1000 | Interval for updating Git information. (Milli seconds) |
<!-- AUTO-GEN:end Git -->


### SyntaxChecker table

<!-- AUTO-GEN:start SyntaxChecker -->
| Name | Type | Default Value | Description |
|:---|:---|:---|:---|
| enable | bool | false | Syntax checker |
<!-- AUTO-GEN:end SyntaxChecker -->


### EditorConfig table

<!-- AUTO-GEN:start EditorConfig -->
| Name | Type | Default Value | Description |
|:---|:---|:---|:---|
| enable | bool | true | [EditorConfig](https://editorconfig.org) support |
<!-- AUTO-GEN:end EditorConfig -->


### SmoothScroll table

<!-- AUTO-GEN:start SmoothScroll -->
| Name | Type | Default Value | Description |
|:---|:---|:---|:---|
| enable | bool | true | Enable smooth scrolling |
| friction | float | 80.0 | Friction coefficient (velocity decay rate) |
| airDrag | float | 2.0 | Air drag coefficient (velocity resistance) |
<!-- AUTO-GEN:end SmoothScroll -->


### KeyMapping table

Persistent key remappings per editor mode. Uses the same key notation as `:nmap`/`:imap` runtime commands.

Values can be either a command name (e.g., `"save"`) or a key sequence (e.g., `"Escape"`).

Supported modes: `All`, `Normal`, `Insert`, `Visual`, `VisualAll`, `VisualLine`, `VisualBlock`, `Replace`, `Command`, `Filer`, `LogViewer`, `Help`, `BufferManager`, `BackupManager`, `DiffViewer`, `Config`, `References`, `DocumentSymbol`, `CallHierarchy`, `RecentFile`, `Debug`, `Terminal`.

`[KeyMapping.All]` applies mappings to all modes (except CommandLine). Mode-specific sections override `All`.

`[KeyMapping.VisualAll]` applies mappings to all visual modes: Visual, VisualLine, and VisualBlock.

`[KeyMapping.Visual]`, `[KeyMapping.VisualLine]`, and `[KeyMapping.VisualBlock]` apply to the specific visual mode only and override `VisualAll`.

Special mode sections (`Filer`, `LogViewer`, `Help`, `BufferManager`, `BackupManager`, `DiffViewer`, `Config`, `References`, `DocumentSymbol`, `CallHierarchy`, `RecentFile`, `Debug`, `Terminal`) apply mappings to the corresponding special mode and override `All`.

```toml
# Apply to all modes (except CommandLine)
[KeyMapping.All]
"C-s" = "save"

# Mode-specific (overrides All for that mode)
[KeyMapping.Normal]
"C-s" = "save"

[KeyMapping.Insert]
"jj" = "Escape"

# Apply to all visual modes (Visual, VisualLine, VisualBlock)
[KeyMapping.VisualAll]
"C-c" = "Escape"

# Characterwise visual mode only (overrides VisualAll)
[KeyMapping.Visual]
"C-c" = "Escape"

# Line-wise visual mode only (overrides VisualAll)
[KeyMapping.VisualLine]
"C-c" = "Escape"

# Block-wise visual mode only (overrides VisualAll)
[KeyMapping.VisualBlock]
"C-c" = "Escape"

[KeyMapping.Replace]
"C-c" = "Escape"

[KeyMapping.Command]
"C-a" = "Home"

# Special modes
[KeyMapping.Filer]
"C-c" = "Escape"

[KeyMapping.LogViewer]
"C-c" = "Escape"

[KeyMapping.Help]
"C-c" = "Escape"

[KeyMapping.BufferManager]
"C-c" = "Escape"

[KeyMapping.BackupManager]
"C-c" = "Escape"

[KeyMapping.DiffViewer]
"C-c" = "Escape"

[KeyMapping.Config]
"C-c" = "Escape"

[KeyMapping.References]
"C-c" = "Escape"

[KeyMapping.DocumentSymbol]
"C-c" = "Escape"

[KeyMapping.CallHierarchy]
"C-c" = "Escape"

[KeyMapping.RecentFile]
"C-c" = "Escape"

[KeyMapping.Debug]
"C-c" = "Escape"

[KeyMapping.Terminal]
"C-c" = "Escape"
```

#### Available commands

Commands are grouped by category below. Any command name listed here can be used as the right-hand side of a `[KeyMapping]` entry.

##### File / buffer / window

| Command | Description |
|:----|:----|
| save | Save file |
| save-and-quit | Save file and quit |
| quit-force | Quit without saving |
| close-window | Close current window |
| file-new | Create new empty buffer |
| file-open | Open file (enter filer) |
| file-close | Close current buffer |
| filer-open | Open file explorer |
| buffer-next-tab | Switch to next buffer tab |
| buffer-prev-tab | Switch to previous buffer tab |
| window-next | Switch to next window |
| window-prev | Switch to previous window |
| window-increase-height | Increase window height |
| window-decrease-height | Decrease window height |
| window-increase-width | Increase window width |
| window-decrease-width | Decrease window width |
| window-equalize | Equalize all window sizes |
| window-swap | Swap window with next window |

##### Mode switching

| Command | Description |
|:----|:----|
| switch-to-normal | Switch to normal mode |
| switch-to-insert | Switch to insert mode |
| switch-to-visual | Switch to visual mode |
| switch-to-visual-line | Switch to visual line mode |
| switch-to-visual-block | Switch to visual block mode |
| switch-to-replace | Switch to replace mode |
| switch-to-command | Switch to command mode |
| switch-to-search | Switch to search mode (forward) |
| switch-to-search-backward | Switch to search mode (backward) |

##### Entering insert mode

| Command | Description |
|:----|:----|
| append | Append after cursor |
| append-end | Append at end of line |
| insert-first-non-blank | Insert at first non-blank character |
| open-line-below | Open new line below and enter insert mode |
| open-line-above | Open new line above and enter insert mode |

##### Cursor motion

| Command | Description |
|:----|:----|
| move-left | Move cursor left |
| move-right | Move cursor right |
| move-up | Move cursor up |
| move-down | Move cursor down |
| page-up | Scroll page up |
| page-down | Scroll page down |
| half-page-up | Scroll half page up |
| half-page-down | Scroll half page down |
| line-home | Move to beginning of line |
| line-end | Move to end of line |
| line-first-non-blank | Move to first non-whitespace character |
| line-last-non-blank | Move to last non-whitespace character |
| next-line-first-non-blank | Move to next line's first non-whitespace character |
| previous-line-first-non-blank | Move to previous line's first non-whitespace character |
| goto-first-line | Go to first line |
| goto-last-line | Go to last line |
| viewport-high | Move to top of viewport |
| viewport-middle | Move to middle of viewport |
| viewport-low | Move to bottom of viewport |
| word-forward | Move to start of next word |
| word-backward | Move to start of previous word |
| word-end | Move to end of next word |
| word-end-backward | Move to end of previous word |
| paragraph-forward | Move to next paragraph |
| paragraph-backward | Move to previous paragraph |
| match-bracket | Jump to matching bracket (%) |
| jump-back | Jump to previous position in jump list |
| jump-forward | Jump to next position in jump list |
| changelist-prev | Jump to previous change position |
| changelist-next | Jump to next change position |
| find-char | Find character forward |
| find-char-backward | Find character backward |
| till-char | Till character forward |
| till-char-backward | Till character backward |

##### Scroll

| Command | Description |
|:----|:----|
| scroll-cursor-top | Scroll cursor to top of screen |
| scroll-cursor-center | Scroll cursor to center of screen |
| scroll-cursor-bottom | Scroll cursor to bottom of screen |

##### Editing

| Command | Description |
|:----|:----|
| undo | Undo last change |
| redo | Redo last undone change |
| delete-char | Delete character at cursor |
| delete-char-before | Delete character before cursor |
| delete-word | Delete word |
| delete-line | Delete line |
| delete-to-end | Delete to end of line |
| change-word | Change word |
| change-to-end | Change to end of line |
| replace-char | Replace character |
| substitute-char | Substitute character at cursor |
| substitute-line | Substitute line |
| toggle-case | Toggle case of character at cursor |
| autoindent-line | Auto indent current line |
| repeat-last-change | Repeat last change |
| join-lines | Join current line with next line |
| increment-number | Increment number at or after cursor |
| decrement-number | Decrement number at or after cursor |

##### Operators (require a motion or text object)

| Command | Description |
|:----|:----|
| operator-change | Change operator |
| operator-delete | Delete operator |
| operator-yank | Yank operator |
| operator-indent | Indent operator |
| operator-outdent | Outdent operator |
| operator-uppercase | Uppercase operator |
| operator-lowercase | Lowercase operator |

##### Text objects (used after an operator)

| Command | Description |
|:----|:----|
| textobject-inner | Inner text object |
| textobject-around | Around text object |
| textobject-word | Word text object |
| textobject-paren | Parenthesis text object |
| textobject-brace | Brace text object |
| textobject-bracket | Bracket text object |
| textobject-quote-single | Single quote text object |
| textobject-quote-double | Double quote text object |

##### Yank / paste / clipboard

| Command | Description |
|:----|:----|
| yank-line | Yank (copy) line |
| paste-after | Paste after cursor |
| paste-before | Paste before cursor |
| clipboard-copy | Copy selected text to system clipboard |
| clipboard-paste | Paste text from system clipboard |
| clipboard-cut | Cut selected text to system clipboard |

##### Search

| Command | Description |
|:----|:----|
| search-next | Find next search result |
| search-prev | Find previous search result |
| search-next-select | Select next search match (gn) |
| search-prev-select | Select previous search match (gN) |
| search-word-forward | Search for word under cursor forward (*) |
| search-word-backward | Search for word under cursor backward (#) |

##### Bookmarks

| Command | Description |
|:----|:----|
| bookmark-toggle | Toggle bookmark on current line |
| bookmark-next | Jump to next bookmark |
| bookmark-prev | Jump to previous bookmark |
| bookmark-clear | Clear all bookmarks in current buffer |

##### Folds

| Command | Description |
|:----|:----|
| fold-open | Open fold at cursor |
| fold-close | Close fold at cursor |
| fold-toggle | Toggle fold at cursor |
| fold-open-all | Open all folds |
| fold-close-all | Close all folds |
| fold-create | Create fold from selection |
| fold-delete | Delete fold at cursor |
| fold-delete-all | Delete all folds |

##### Visual mode

| Command | Description |
|:----|:----|
| visual-move-left | Move left in visual mode |
| visual-move-right | Move right in visual mode |
| visual-move-up | Move up in visual mode |
| visual-move-down | Move down in visual mode |
| visual-move-home | Move to beginning of line in visual mode |
| visual-move-end | Move to end of line in visual mode |
| visual-move-firstnonblank | Move to first non-blank character in visual mode |
| visual-move-firstline | Move to first line in visual mode |
| visual-move-lastline | Move to last line in visual mode |
| visual-move-word | Move to next word in visual mode |
| visual-move-word-back | Move to previous word in visual mode |
| visual-move-word-end | Move to end of word in visual mode |
| visual-move-word-end-backward | Move to end of previous word in visual mode |
| visual-move-paragraph-forward | Move to next paragraph in visual mode |
| visual-move-paragraph-backward | Move to previous paragraph in visual mode |
| visual-yank | Yank visual selection |
| visual-delete | Delete visual selection |
| visual-change | Delete selection and enter insert mode |
| visual-paste | Delete selection and paste register content |
| visual-indent | Indent visual selection |
| visual-dedent | Dedent visual selection |
| visual-joinlines | Join lines in visual selection |
| visual-uppercase | Convert visual selection to uppercase |
| visual-lowercase | Convert visual selection to lowercase |
| visual-toggle-case | Toggle case of visual selection |
| visual-replace-char | Replace visual selection with character |
| visual-surround-char | Surround visual selection with character |
| visual-swap-selection | Swap cursor to other end of selection |
| visual-to-insert | Enter insert mode from visual selection |
| visual-block-append | Append after visual block selection |

##### LSP

| Command | Description |
|:----|:----|
| lsp-goto-definition | Go to definition (LSP) |
| lsp-goto-declaration | Go to declaration (LSP) |
| lsp-goto-type-definition | Go to type definition (LSP) |
| lsp-goto-implementation | Go to implementation (LSP) |
| lsp-find-references | Find all references (LSP) |
| lsp-hover | Show hover information (LSP) |
| lsp-rename | Rename symbol (LSP) |
| lsp-document-symbol | Show document symbols (LSP) |
| lsp-document-link | Follow document link at cursor (LSP) |
| lsp-selection-range | Expand selection range (LSP) |
| lsp-codelens-execute | Execute CodeLens on current line (LSP) |
| lsp-call-hierarchy | Show call hierarchy (LSP) |
| lsp-call-hierarchy-outgoing | Show outgoing call hierarchy (LSP) |

##### Git navigation

| Command | Description |
|:----|:----|
| navigate-git-next | Next git change |
| navigate-git-prev | Previous git change |
| navigate-conflict-next | Next git merge conflict |
| navigate-conflict-prev | Previous git merge conflict |

##### Macro / register

| Command | Description |
|:----|:----|
| macro-record | Start/stop macro recording |
| macro-play | Play macro from register |
| register-select | Select register for next command |

##### Insert-mode keys

| Command | Description |
|:----|:----|
| insert-backspace | Delete character before cursor (insert mode) |
| insert-delete | Delete character at cursor (insert mode) |
| insert-newline | Insert newline (insert mode) |

##### Miscellaneous

| Command | Description |
|:----|:----|
| quickrun | Run current buffer |
| show-char-info | Show ASCII/Unicode value of character under cursor |
| open-uri | Open URI/file under cursor |

##### Command mode command aliases

The following Vim-style short names are also accepted as the right-hand side of a
`[KeyMapping]` (and `keybindings.toml` `command`) entry. They are dispatched
through the full Command mode (`:`) parser, so safety checks like the
modified-buffer guard for `:bdelete` / `:quit` apply automatically.

| Alias | Description |
|:----|:----|
| bn / bnext | Switch to next buffer |
| bp / bprev / bprevious | Switch to previous buffer |
| bf / bfirst | Switch to first buffer |
| bl / blast | Switch to last buffer |
| bd / bdelete | Delete current buffer |
| q / quit | Quit |
| qa / quitall | Quit all |
| w / save | Save current buffer |
| wa / saveall | Save all buffers |
| wq | Save and quit |
| wqa | Save all and quit |

Example:

```toml
[KeyMapping.Normal]
"K" = "bdelete"
"F2" = "wq"
```

#### Application order

Key mappings are applied in this order (later overrides earlier):

1. Built-in default bindings
2. `keybindings.toml`
3. `moerc.toml` `[KeyMapping.All]`
4. `moerc.toml` `[KeyMapping.VisualAll]`
5. `moerc.toml` mode-specific sections (`[KeyMapping.Normal]`, `[KeyMapping.Visual]`, `[KeyMapping.Filer]`, etc.)
6. Runtime `:nmap`/`:imap`/`:cmap` commands

Also see [Runtime Key Mapping](howtouse.md#runtime-key-mapping) for session-only mappings.


### keybindings.toml

An alternative keybinding configuration file with typed commands and richer options than `[KeyMapping]`.

The file is searched in the following locations (in order):

1. `$XDG_CONFIG_HOME/moe/keybindings.toml`
2. `~/.config/moe/keybindings.toml`
3. `./keybindings.toml` (current directory)

Each keybinding is defined as a `[[keybinding]]` entry.

#### Required fields

| Field | Type | Description |
|:---|:---|:---|
| mode | string | Editor mode (see below) |
| key | string | Key or key sequence to bind |

#### Supported modes

Individual modes: `normal`, `insert`, `visual`, `visualline`, `visualblock`, `replace`, `command`, `filer`, `quickrun`, `logviewer`, `help`, `buffermanager`, `backupmanager`, `diffviewer`, `recentfile`, `debug`, `config`, `references`, `documentsymbol`, `callhierarchy`, `terminal`.

Meta modes:
- `all` - All modes except Command mode
- `visualall` - Visual, VisualLine, VisualBlock

#### Command types

| command_type | Required field | Description |
|:---|:---|:---|
| `action` (default) | `command` | General editor action |
| `mode_switch` | `target_mode` | Switch editor mode |
| `overlay_switch` | `target_overlay` | Switch to overlay (one of: `command`, `search`, `rename`) |
| `text_object` | `command` | Text object operation |
| `operator` | `command` | Vim-style operator |
| `custom` | `command` | User-defined command |
| `key_sequence` | `target_keys` | Remap key to another key sequence |

Optional field `args` (array of strings) is available for `action`, `text_object`, `operator`, and `custom` types.

#### Key notation

- Single character: `"h"`, `"j"`
- Modifiers: `"C-s"` (Ctrl), `"M-x"` (Alt/Meta), `"S-Tab"` (Shift), `"C-M-s"` (combined)
- Special keys: `"Escape"`, `"Enter"`, `"Tab"`, `"Backspace"`, `"Delete"`, `"Space"`, `"Up"`, `"Down"`, `"Left"`, `"Right"`, `"PageUp"`, `"PageDown"`, `"Home"`, `"End"`, `"F1"`-`"F12"`
- Multi-key sequences: `"g d"` (space-separated), `"jj"` (Vim-style concatenated)

#### Examples

```toml
# Action: bind Ctrl-s to save
[[keybinding]]
mode = "normal"
key = "C-s"
command = "save"

# Mode switch: Escape to normal mode
[[keybinding]]
mode = "insert"
key = "Escape"
command_type = "mode_switch"
target_mode = "normal"

# Overlay switch: open search overlay
[[keybinding]]
mode = "normal"
key = "C-f"
command_type = "overlay_switch"
target_overlay = "search"

# Key sequence remap: jj to Escape in insert mode
[[keybinding]]
mode = "insert"
key = "jj"
command_type = "key_sequence"
target_keys = "Escape"

# Multi-key sequence: g d to goto definition
[[keybinding]]
mode = "normal"
key = "g d"
command = "lsp-goto-definition"

# All modes (except Command mode)
[[keybinding]]
mode = "all"
key = "C-q"
command = "quit-force"

# Custom command with args
[[keybinding]]
mode = "normal"
key = "C-p"
command_type = "custom"
command = "search.forward"
args = ["case_sensitive"]
```

#### Available commands

The same commands as `[KeyMapping]` are available. See [Available commands](#available-commands) above.


### Lsp table

| Name | Type | Default Value | Description |
|:-----------------------------|:-----------------------------|:---------------------------|:---------------------------|
| enable | bool | false | LSP (Language Server Protocol) Client |
| timeout | integer | 5000 | Timeout in milliseconds for LSP requests (0 = no timeout) |


### Lsp.Completion table

| Name | Type | Default Value | Description |
|:-----------------------------|:-----------------------------|:---------------------------|:---------------------------|
| enable | bool | true | LSP Completion |


### Lsp.Declaration table

| Name | Type | Default Value | Description |
|:-----------------------------|:-----------------------------|:---------------------------|:---------------------------|
| enable | bool | true | LSP Goto Declaration |
| openWindow | bool | false | Open a new window and jump |


### Lsp.Definition table

| Name | Type | Default Value | Description |
|:-----------------------------|:-----------------------------|:---------------------------|:---------------------------|
| enable | bool | true | LSP Goto Definition |
| openWindow | bool | false | Open a new window and jump |


### Lsp.TypeDefinition table

| Name | Type | Default Value | Description |
|:-----------------------------|:-----------------------------|:---------------------------|:---------------------------|
| enable | bool | true | LSP Type Definition |
| openWindow | bool | false | Open a new window and jump |


### Lsp.Implementation table

| Name | Type | Default Value | Description |
|:-----------------------------|:-----------------------------|:---------------------------|:---------------------------|
| enable | bool | true | LSP Implementation |
| openWindow | bool | false | Open a new window and jump |


### Lsp.Diagnostics table

| Name | Type | Default Value | Description |
|:-----------------------------|:-----------------------------|:---------------------------|:---------------------------|
| enable | bool | true | LSP Diagnostics |
| autoHover | bool | true | Automatically show diagnostic messages in hover popup when cursor is on a diagnostic |
| autoHoverDelay | integer | 300 | Delay in milliseconds before auto hover shows (0 = no delay) |


### Lsp.SignatureHelp table

| Name | Type | Default Value | Description |
|:-----------------------------|:-----------------------------|:---------------------------|:---------------------------|
| enable | bool | true | LSP Signature Help |


### Lsp.DocumentFormatting table

| Name | Type | Default Value | Description |
|:-----------------------------|:-----------------------------|:---------------------------|:---------------------------|
| enable | bool | true | LSP Document Formatting |


### Lsp.FoldingRange table

| Name | Type | Default Value | Description |
|:-----------------------------|:-----------------------------|:---------------------------|:---------------------------|
| enable | bool | true | LSP Folding Range |


### Lsp.SelectionRange table

| Name | Type | Default Value | Description |
|:-----------------------------|:-----------------------------|:---------------------------|:---------------------------|
| enable | bool | true | LSP Selection Range |


### Lsp.DocumentSymbol table

| Name | Type | Default Value | Description |
|:-----------------------------|:-----------------------------|:---------------------------|:---------------------------|
| enable | bool | true | LSP Document Symbol |


### Lsp.Hover table

| Name | Type | Default Value | Description |
|:-----------------------------|:-----------------------------|:---------------------------|:---------------------------|
| enable | bool | true | LSP Hover |


### Lsp.InlayHint table

| Name | Type | Default Value | Description |
|:-----------------------------|:-----------------------------|:---------------------------|:---------------------------|
| enable | bool | true | LSP InlayHint |


### Lsp.InlineValue table

| Name | Type | Default Value | Description |
|:-----------------------------|:-----------------------------|:---------------------------|:---------------------------|
| enable | bool | false | LSP InlineValue |


### Lsp.References table

| Name | Type | Default Value | Description |
|:-----------------------------|:-----------------------------|:---------------------------|:---------------------------|
| enable | bool | true | LSP Find References |


### Lsp.CallHierarchy table

| Name | Type | Default Value | Description |
|:-----------------------------|:-----------------------------|:---------------------------|:---------------------------|
| enable | bool | true | LSP Call Hierarchy |


### Lsp.DocumentHighlight table

| Name | Type | Default Value | Description |
|:-----------------------------|:-----------------------------|:---------------------------|:---------------------------|
| enable | bool | true | LSP Document Highlight |


### Lsp.DocumentLink table

| Name | Type | Default Value | Description |
|:-----------------------------|:-----------------------------|:---------------------------|:---------------------------|
| enable | bool | true | LSP Document Link |


### Lsp.CodeLens table

| Name | Type | Default Value | Description |
|:-----------------------------|:-----------------------------|:---------------------------|:---------------------------|
| enable | bool | false | LSP Code Lens |


### Lsp.Rename table

| Name | Type | Default Value | Description |
|:-----------------------------|:-----------------------------|:---------------------------|:---------------------------|
| enable | bool | true | LSP Rename |


### Lsp.SemanticTokens table

| Name | Type | Default Value | Description |
|:-----------------------------|:-----------------------------|:---------------------------|:---------------------------|
| enable | bool | true | LSP Semantic Tokens |


### Lsp.ExecuteCommand table

| Name | Type | Default Value | Description |
|:-----------------------------|:-----------------------------|:---------------------------|:---------------------------|
| enable | bool | true | LSP Execute Command |


### LspTraceLevel

- type: string

| Name |
|:-----------------------------|
| off |
| messages |
| verbose |


### Lsp.{languageId} table

| Name | Type | Default Value | Description |
|:-----------------------------|:-----------------------------|:---------------------------|:---------------------------|
| extensions | Array of string | | File extensions |
| command | string | | LSP server command |
| trace | LspTraceLevel | off | LSP trace level for debugging |
| rustAnalyzerRunSingle | bool | true | `rust-analyzer.runSingle`. Only effective with rust-analyzer and if `Lsp.CodeLens` is enabled. |
| rustAnalyzerDebugSingle | bool | true | `rust-analyzer.debugSingle`. Only effective with rust-analyzer and if `Lsp.CodeLens` is enabled. |


Please check more [details](https://github.com/fox0430/moe/blob/develop/documents/lsp.md)

### StartUp.FileOpen table

<!-- AUTO-GEN:start StartUp.FileOpen -->
| Name | Type | Default Value | Description |
|:---|:---|:---|:---|
| autoSplit | bool | true | Display all buffers in multiple views if multiple paths are received when starting the editor |
| splitType | string (enum: horizontal, vertical) | vertical | The split type for `StartUp.FileOpen.autoSplit` |
<!-- AUTO-GEN:end StartUp.FileOpen -->


### FileTree table

<!-- AUTO-GEN:start FileTree -->
| Name | Type | Default Value | Description |
|:---|:---|:---|:---|
| width | integer | 30 | Width of the FileTree sidebar in columns |
<!-- AUTO-GEN:end FileTree -->


### StartUp.FileTree table

<!-- AUTO-GEN:start StartUp.FileTree -->
| Name | Type | Default Value | Description |
|:---|:---|:---|:---|
| enable | bool | false | Open the fileTree sidebar automatically on startup |
<!-- AUTO-GEN:end StartUp.FileTree -->


### CommandAliases table

Define custom aliases for built-in editor commands.
Each key is the alias name, and the value is a table with `command` and optional `description`.
Built-in aliases can be overridden.

Example:
```toml
[CommandAliases]
x = { command = "quit" }
ww = { command = "saveall", description = "Save all buffers" }
fmt = { command = "lspformat", description = "Format code with LSP" }
```

| Key | Type | Required | Description |
|:----|:-----|:---------|:------------|
| command | string | yes | Built-in command name (see table below) |
| description | string | no | Custom description shown in completion popup |

Available command names:

| Name | Description |
|:-----------------------------|:-----------------------------|
| quit | Quit |
| quitall | Quit all |
| save | Save |
| saveall | Save all |
| saveandquit | Save and quit |
| saveallandquit | Save all and quit |
| edit | Edit file |
| enew | New empty buffer |
| set | Set option |
| help | Help |
| substitute | Substitute |
| vsplit | Vertical split |
| hsplit | Horizontal split |
| new | New buffer in horizontal split |
| vnew | New buffer in vertical split |
| buffernext | Next buffer |
| bufferprev | Previous buffer |
| bufferfirst | First buffer |
| bufferlast | Last buffer |
| bufferdelete | Delete buffer |
| buffer | Switch to buffer |
| stripwhitespace | Strip trailing whitespace |
| filer | Open file explorer |
| log | Open log viewer |
| quickrun | Quick run |
| buffermanager | Open buffer manager |
| backup | Open backup manager |
| recent | Open recent file |
| noh | Clear search highlight |
| shell | Execute shell command |
| background | Pause editor |
| jumplist | Show jump list |
| changes | Show change list |
| bookmarks | Show bookmarks |
| build | Build |
| debug | Debug mode |
| config | Configuration mode |
| putconfigfile | Write sample config file |
| man | Show manual |
| theme | Change theme |
| terminal | Open terminal |
| only | Close all other windows |
| lsplog | LSP log viewer |
| lspformat | LSP format |
| lsprestart | LSP restart |
| lspfold | LSP folding range |
| lspexecommand | LSP execute command |
| lspcallhierarchyincoming | LSP incoming calls |
| lspcallhierarchyoutgoing | LSP outgoing calls |


### ShellCommands table

Define shell commands that can be invoked from command mode.
Each key is the command name, and the value is a table with `command` and optional `description`.
Arguments are appended to the shell command.
Built-in commands and aliases always take priority over shell commands.

Example:
```toml
[ShellCommands]
nimbuild = { command = "nimble build", description = "Build project" }
nimtest = { command = "nimble test" }
gitlog = { command = "git log --oneline -20", description = "Recent commits" }
```

| Key | Type | Required | Description |
|:----|:-----|:---------|:------------|
| command | string | yes | Shell command to execute |
| description | string | no | Custom description shown in completion popup (default: `Shell: <command>`) |

Usage:
- `:nimbuild` runs `nimble build`
- `:nimbuild --release` runs `nimble build --release`


### Theme table
| Name | Type | Default Value | Description |
|:-----------------------------|:-----------------------------|:---------------------------|:---------------------------|
| kind | ThemeKind | config | Theme kind |
| path | string | ~/.config/moe/themes/dark.toml | A path of user theme. Also Please set `"config"` to `Theme.kind`. |


### Color table (Theme)
Put the toml file that describes the `Colors` table in the path specified by `Theme.path` in `moerc.toml`.

moe supports 24 bit color and set in hexadecimal (`#000000` ~ `#ffffff`).
And, `termDefault` can be used for both foreground and background to use the terminal's default color.

Each entry under `[Colors]` is an inline table that sets `fg` and/or `bg`,
for example `lineNum = { fg = "#636d83", bg = "#000000" }`. The top-level
`foreground` and `background` keys override the editor's default text and
background colors, which all other entries inherit when their `bg` is
omitted.

#### Migrating from the legacy format

Earlier versions used separate flat keys for foreground and background
(`lineNum = "#636d83"` / `lineNumBg = "#000000"`). User themes written in
that format can be converted with `tools/migrate_theme_toml.nim`:

```sh
nim r tools/migrate_theme_toml.nim path/to/theme.toml             # print to stdout
nim r tools/migrate_theme_toml.nim --in-place path/to/theme.toml  # rewrite in place (original saved as .bak)
nim r tools/migrate_theme_toml.nim --check path/to/theme.toml     # exit 0 if already migrated
```

The tool is idempotent — re-running it on an already-migrated file is a no-op.

Notes:

- Comments (header and inline) are not preserved; the output is rebuilt from
  the parsed TOML AST. Move any hand-written notes out of your theme file
  before running `--in-place`.
- Only the `[Colors]` section is emitted; any other top-level sections in
  the input are dropped.
- `--in-place` overwrites an existing `<file>.bak` without warning.

<!-- AUTO-GEN:start Colors -->
| Name | Description |
|:---|:---|
| foreground | Default foreground color (overrides `Colors.default.fg`) |
| background | Default background color (overrides `Colors.default.bg`) |
| lineNum | Line number gutter |
| currentLineNum | Current line number highlight |
| sidebarSessionModifiedSign | Sidebar: modified line sign |
| sidebarSessionInsertedSign | Sidebar: inserted line sign |
| statusLineNormalMode | Status line in Normal mode (active) |
| statusLineNormalModeLabel | Status line mode label in Normal mode |
| statusLineNormalModeInactive | Status line in Normal mode (inactive) |
| statusLineInsertMode | Status line in Insert mode (active) |
| statusLineInsertModeLabel | Status line mode label in Insert mode |
| statusLineInsertModeInactive | Status line in Insert mode (inactive) |
| statusLineVisualMode | Status line in Visual mode (active) |
| statusLineVisualModeLabel | Status line mode label in Visual mode |
| statusLineVisualModeInactive | Status line in Visual mode (inactive) |
| statusLineReplaceMode | Status line in Replace mode (active) |
| statusLineReplaceModeLabel | Status line mode label in Replace mode |
| statusLineReplaceModeInactive | Status line in Replace mode (inactive) |
| statusLineFilerMode | Status line in Filer mode (active) |
| statusLineFilerModeLabel | Status line mode label in Filer mode |
| statusLineFilerModeInactive | Status line in Filer mode (inactive) |
| statusLineExMode | Status line in Command mode (active) |
| statusLineExModeLabel | Status line mode label in Command mode |
| statusLineExModeInactive | Status line in Command mode (inactive) |
| statusLineGitChangedLines | Status line git changed-lines counter |
| statusLineGitBranch | Status line git branch name |
| tab | Tab title in the tab line |
| currentTab | Current tab title in the tab line |
| commandLine | Command line |
| errorMessage | Error message |
| warnMessage | Warning message |
| searchResult | Search result highlight |
| findCharMatch | f/F/t/T character match highlight |
| selectArea | Visual mode selection |
| keyword | Syntax: keyword |
| functionName | Syntax: function name |
| typeName | Syntax: type name |
| boolean | Syntax: boolean literal |
| specialVar | Syntax: special variable |
| builtin | Syntax: builtin |
| charLit | Syntax: character literal |
| stringLit | Syntax: string literal |
| binNumber | Syntax: binary number literal |
| decNumber | Syntax: decimal number literal |
| floatNumber | Syntax: floating-point number literal |
| hexNumber | Syntax: hexadecimal number literal |
| octNumber | Syntax: octal number literal |
| comment | Syntax: line comment |
| longComment | Syntax: block/long comment |
| docComment | Syntax: documentation comment |
| docLongComment | Syntax: long documentation comment |
| whitespace | Syntax: whitespace indicator |
| preprocessor | Syntax: preprocessor directive |
| pragma | Syntax: pragma |
| identifier | Syntax: identifier |
| table | Syntax: TOML table header |
| date | Syntax: date literal |
| logError | Log file error level |
| logWarning | Log file warning level |
| logInfo | Log file info/debug level |
| logUuid | Log file UUID |
| operator | Syntax: operator |
| property | Syntax: property |
| markdownCodeBlock | Markdown code block |
| namespace | LSP semantic token: namespace |
| className | LSP semantic token: class name |
| enumName | LSP semantic token: enum name |
| enumMember | LSP semantic token: enum member |
| interfaceName | LSP semantic token: interface name |
| typeParameter | LSP semantic token: type parameter |
| parameter | LSP semantic token: parameter |
| variable | LSP semantic token: variable |
| string | LSP semantic token: string |
| event | LSP semantic token: event |
| function | LSP semantic token: function |
| method | LSP semantic token: method |
| macro | LSP semantic token: macro |
| regexp | LSP semantic token: regular expression |
| decorator | LSP semantic token: decorator |
| angle | LSP semantic token: angle bracket |
| arithmetic | LSP semantic token: arithmetic operator |
| attribute | LSP semantic token: attribute |
| attributeBracket | LSP semantic token: attribute bracket |
| bitwise | LSP semantic token: bitwise operator |
| brace | LSP semantic token: brace |
| bracket | LSP semantic token: bracket |
| builtinAttribute | LSP semantic token: builtin attribute |
| builtinType | LSP semantic token: builtin type |
| colon | LSP semantic token: colon |
| comma | LSP semantic token: comma |
| comparison | LSP semantic token: comparison operator |
| constParameter | LSP semantic token: const parameter |
| derive | LSP semantic token: derive |
| deriveHelper | LSP semantic token: derive helper |
| dot | LSP semantic token: dot |
| escapeSequence | LSP semantic token: escape sequence |
| invalidEscapeSequence | LSP semantic token: invalid escape sequence |
| formatSpecifier | LSP semantic token: format specifier |
| generic | LSP semantic token: generic |
| label | LSP semantic token: label |
| lifetime | LSP semantic token: lifetime |
| logical | LSP semantic token: logical operator |
| macroBang | LSP semantic token: macro bang (`!`) |
| parenthesis | LSP semantic token: parenthesis |
| punctuation | Syntax: punctuation |
| selfKeyword | LSP semantic token: `self` keyword |
| selfTypeKeyword | LSP semantic token: `Self` type keyword |
| semicolon | LSP semantic token: semicolon |
| typeAlias | LSP semantic token: type alias |
| toolModule | LSP semantic token: tool module |
| union | LSP semantic token: union |
| unresolvedReference | LSP semantic token: unresolved reference |
| inlayHint | LSP inlay hint |
| inlineValue | LSP inline value |
| codeLens | LSP code lens |
| currentFile | Filer: current file name |
| file | Filer: file name |
| dir | Filer: directory name |
| pcLink | Filer: symbolic link |
| popupWindow | Pop-up window |
| popupWinCurrentLine | Pop-up window current line |
| notificationPopupInfo | Notification popup: info body |
| notificationPopupInfoBorder | Notification popup: info border |
| notificationPopupWarning | Notification popup: warning body |
| notificationPopupWarningBorder | Notification popup: warning border |
| notificationPopupError | Notification popup: error body |
| notificationPopupErrorBorder | Notification popup: error border |
| replaceText | Replace command replacement text |
| parenPair | Matching bracket pair highlight |
| currentWord | Other occurrences of the word under cursor |
| highlightFullWidthSpace | Full-width space highlight |
| highlightTrailingSpaces | Trailing whitespace highlight |
| reservedWord | Reserved word highlight |
| syntaxCheckInfo | Syntax checker: info diagnostic |
| syntaxCheckHint | Syntax checker: hint diagnostic |
| syntaxCheckWarn | Syntax checker: warning diagnostic |
| syntaxCheckErr | Syntax checker: error diagnostic |
| gitConflict | Git conflict block (single-color fallback when gitConflictTwoColor = false) |
| gitConflictMarker | Git conflict marker lines (`<<<<<<<`, `\|\|\|\|\|\|\|`, `=======`, `>>>>>>>`) |
| gitConflictOurs | Git conflict: "ours" side |
| gitConflictBase | Git conflict: diff3 "base" side |
| gitConflictTheirs | Git conflict: "theirs" side |
| backupManagerCurrentLine | Backup manager: current line |
| diffViewerAddedLine | Diff viewer: added line |
| diffViewerDeletedLine | Diff viewer: deleted line |
| configModeCurrentLine | Configuration mode: current line |
| currentLine | Editor current line background (bg-only) |
| currentColumn | Editor current column background (bg-only) |
| foldingLine | Folded-region indicator line |
| sidebarGitAddedSign | Sidebar: git added sign |
| sidebarGitDeletedSign | Sidebar: git deleted sign |
| sidebarGitChangedSign | Sidebar: git changed sign |
| sidebarGitConflictSign | Sidebar: git conflict sign |
| sidebarSyntaxCheckInfoSign | Sidebar: syntax checker info sign |
| sidebarSyntaxCheckHintSign | Sidebar: syntax checker hint sign |
| sidebarSyntaxCheckWarnSign | Sidebar: syntax checker warning sign |
| sidebarSyntaxCheckErrSign | Sidebar: syntax checker error sign |
| viewerHeader | Viewer common: header |
| viewerSelectedLine | Viewer common: selected line |
| viewerEmptyMessage | Viewer common: empty-state message |
| filerDirectory | Filer: directory entry |
| filerSymlink | Filer: symbolic link entry |
| filerSymlinkDir | Filer: symbolic link to directory |
| filerHiddenFile | Filer: hidden file entry |
| filerExecutable | Filer: executable file entry |
| bufferManagerActive | Buffer manager: active buffer |
| bufferManagerModified | Buffer manager: modified buffer |
| configModeSection | Configuration mode: section header |
| configModeEditMode | Configuration mode: edit mode indicator |
| configModePopup | Configuration mode: popup body and border |
| configModePopupSelected | Configuration mode: popup selected entry |
| diffViewerHeader | Diff viewer: header |
| diffViewerMeta | Diff viewer: metadata line |
| recentFileMissing | Recent file mode: missing file entry |
| debugViewerSectionHeader | Debug viewer: section header |
| referencesViewerHeader | References viewer: header |
| documentSymbolViewerHeader | Document symbol viewer: header |
| callHierarchyViewerHeader | Call hierarchy viewer: header |
| helpViewerSectionHeader | Help viewer: section header |
<!-- AUTO-GEN:end Colors -->
