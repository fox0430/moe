# Configuration file

Write moe's configuration file in toml.  
The location is

```
~/.config/moe/moerc.toml
```

You can use the example -> https://github.com/fox0430/moe/blob/develop/example/moerc.toml

## Setting items

### Standard table
Color theme (String)
`"vivid"` or `"dark"` or `"light"` or `"vscode"`
default is `"dark"`.
```
theme
```

Note: `"vscode"` is you can use current VSCode/VSCodium theme. Check [#648](https://github.com/fox0430/moe/pull/648)

Display line numbers (bool)  
default is true
```
number
```

Display status line (bool)  
default is true
```
statusLine
```

Enable syntax highlighting (bool)  
default is true
```
syntax
```

Enable/Disable indentation lines (bool)  
default is true
```
indentationLines
```

Set tab width (integer)  
default is 2
```
tabStop
```

Enable/Disable sidebars for editor views (bool)
default is true
```
sidebar
```

Enable/Disable ignorecase (bool)  
default is true
```
ignorecase
```

Enable/Disable smartcase (bool)  
default is true
```
smartcase
```

Automatic closing brackets (bool)  
default is true
```
autoCloseParen
```

Automatic indentation (bool)  
default is true
```
autoIndent
```

Disable change of the cursor shape (bool)  
default is false
```
disableChangeCursor
```

Set cursor shape of the terminal emulator you are using (String) `"terminalDefault"` or `"blinkBlock"` or `"blinkIbeam"` or `noneBlinkBlock` or `noneBlinkIbeam`  
default is `"terminalDefault"`
```
defaultCursor
```

Set cursor shape in normal mode (String) `"terminalDefault"` or `"blinkBlock"` or `"blinkIbeam"` or `noneBlinkBlock` or `noneBlinkIbeam`  
default is `"blinkBlock"`
```
normalModeCursor
```

Set cursor shape in insert mode (String) `"terminalDefault"` or `"blinkBlock"` or `"blinkIbeam"` or `noneBlinkBlock` or `noneBlinkIbeam`  
default is `"blinkIbeam"`

```
insertModeCursor
```

Live reload of configuration file (bool)  
default is false
```
liveReloadOfConf
```

Incremental search (bool)  
default is true
```
incrementalSearch
```

Pop-up window in ex mode (bool)  
default is true
```
popUpWindowInExmode 
```

Auto delete paren (bool)  
default is false
```
autoDeleteParen
```

Live reloading open files (bool)  
default is false
```
liveReloadOfFile
```

Terminal color mode (string) `none` or `8` or `16` or `256` or `24bit`
defualt is "24bit"
```
colorMode
```

### Clipboard table
Enable/Disable system clipboard (bool)  
default is true
```
enable
```

Set clipboard tool for Linux (string)  
default is xsel

`xsel`, `xclip`, `wl-clipboard`, `wsl-default`, `macOS-default`.

```
tool
```

### TabLine table
Show all bufer in tab line (bool)  
default is false  
```
allBuffer
```

### StatusLine table
Multiple status line (bool)  
default is true
```
multipleStatusLine
```

Enable/Disable merging status line with command line (bool)  
default is true
```
merge
```

Show current mode (bool)  
default is true
```
mode
```

Show edit history mark (bool)  
default is true
```
chanedMark
```

Show file location (bool)  
default is true
```
directory
```

Show current git branch name (bool)  
default is true
```
gitbranchName
```

Show number of changed lines (bool)  
defualt is true
```
showChangedLine
```

Show/Hide git branch name in status line when window is inactive (bool)  
default is false
```
showGitInactive
```

Show/Hide mode string in status line when window is inactive (bool)  
default is false
```
showModeInactive
```

Text to customize the items displayed in the status line (string)

Items: `lineNumber`, `totalLines` `columnNumber`, `totalColumns`,  `encoding`, `fileType`, `fileTypeIcon`

You can display information in the status lien by enclosing the above items in parentheses. Example: `{lineNumber}`

defaut is `"{lineNumber}/{totalLines} {columnNumber}/{totalColumns} {encoding} {fileType}"`
```
setupText
```

### BuildOnSave table

Enable/Disable build on save (bool)  
default is false
```
buildOnSave
```

Project root directory (string)  
```
workspaceRoot
```

Override commands executed at build (string)  
```
command
```

### Highlight table

Highlight the current line (bool)  
defaut is true
```
currentLine

```

Highlight any word (array)  

defaut
```
["TODO", "WIP", "NOTE"]
```
```
reservedWord
```

Highlight replacement text (bool)  
default is true
```
replaceText
```

Highlight a pair of paren (bool)  
default is true
```
pairOfParen
```

Highlight full-width space (bool)  
default is true
```
fullWidthSpace
```

Highlight trailing spaces (bool)  
default is true
```
trailingSpaces
```

highlight other uses of the current word under the cursor (bool)  
default is true
```
currentWord
```

### AutoBackup table

Enable/Disable automatic backups (bool)  
default is false
```
enable
```

Start backup when there is no operation for the set number of seconds (int)  
default is 10 (10 second)  
```
idleTime
```

Backup interval (int)  
default is 5 (5 minute)    
```
interval
```

Directory to save backup files (string)  
default is "" (`~/.cache/moe/backups`)    
```
backupDir
```

Exclude settings for where you don't want to produce automatic backups (array)  
default
```
["/etc"]
```

```
dirToExclude
```

### QuickRun table

Save buffer when run QuickRun (bool)  
default is true
```
saveBufferWhenQuickRun
```

Setting commands to be executed by quick run (string)  
default is "" (None)
```
command
```

Command timeout (int)  
default is 30 (30 second)
```
timeout
```

Nim compiler advanced command setting (string)  
default is "c"
```
nimAdvancedCommand
```

gcc compileer option setting (string)  
default is "" (None)
```
ClangOptions
```

g++ compiler option setting (string)  
default is "" (None)
```
CppOptions
```

Nim compiler option setting (string)  
default is "" (None)
```
NimOptions
```

sh option setting (string)  
default is "" (None)
```
shOptions
```

bash option setting (string)  
default is "" (None)
```
bashOptions
```

### Notification table

Enable/disable all messages/notifications in status line (bool)  
default is true
```
screenNotifications
```

Enable/disable all messages/notifications in log (bool)  
default is true
```
logNotifications
```

Enable/disable auto backups messages/notifications in status line (bool)  
default is true
```
autoBackupScreenNotify
```

Enable/disable auto backups messages/notifications in log (bool)  
default is true
```
autoBackupLogNotify
```

Enable/disable auto save messages/notifications in status line (bool)  
default is true
```
autoSaveScreenNotify
```

Enable/disable auto save messages/notifications in log (bool)  
default is true
```
autoSaveLogNotify
```

Enable/disable yank messages/notifications in status line (bool)  
default is true
```
yankScreenNotify
```

Enable/disable yank messages/notifications in log (bool)  
default is true
```
yankLogNotify
```

Enable/disable delete buffer messages/notifications in status line (bool)  
default is true
```
deleteScreenNotify
```

Enable/disable delete buffer messages/notifications in log (bool)  
default is true
```
deleteLogNotify
```

Enable/disable save messages/notifications in status line (bool)  
default is true
```
saveScreenNotify
```

Enable/disable save messages/notifications in log (bool)  
default is true
```
saveLogNotify
```

Enable/disable QuickRun messages/notifications in status line (bool)  
default is true
```
quickRunScreenNotify
```

Enable/disable QuickRun messages/notifications in log (bool)  
default is true
```
quickRunLogNotify
```

Enable/disable build on save messages/notifications in status line (bool)  
default is true
```
buildOnSaveScreenNotify
```

Enable/disable build on save messages/notifications in log (bool)  
default is true
```
buildOnSaveLogNotify
```

Enable/disable filer messages/notifications in status line (bool)  
default is true
```
filerScreenNotify
```

Enable/disable filer messages/notifications in log (bool)  
default is true
```
filerLogNotify
```

Enable/disable restore messages/notifications in status line (bool)  
default is true
```
restoreScreenNotify
```

Enable/disable restore messages/notifications in log (bool)  
default is true
```
restoreLogNotify
```

### Filer table

Show/hidden unicode icons (bool)  
default is true
```
showIcons
```

### Autocomplete table

Enable/Disable general-purpose autocomplete (bool).
The default value is true.
```
enable
```

### AutoSave table
Enable/Disable auto save (bool)  
default is true
```
enable
```

Auto save interval (minits) (int)  
default is 5 (5 minits)
```
interval
```

### Persist table

Enable/Disable saving Ex command history (bool).
The default value is true.
```
exCommand
```

The maximum entries of ex command history to save (int).
The defaut value is 1000.
```
exCommandHistoryLimit
```

Enable/Disable saving search history (bool).
The default value is true.
```
search
```

The maximum entries of search history to save (int).
The defaut value is 1000.
```
searchHistoryLimit
```

Enable/Disable saving last cursor position (bool).
The default value is true.
```
curosrPosition
```

### Debug.WindowNode table

Show/Hidden all windowNode info in debug mode (bool)
```
enable
```

Show/Hidden whether the current window or not in debug mode (bool)
```
currentWindow
```

Show/Hidden windowNode.index in debug mode (bool)
```
index
```

Show/Hidden windowNode.windowIndex in debug mode (bool)
```
windowIndex
```

Show/Hidden windowNode.bufferIndex in debug mode (bool)
```
bufferIndex
```

Show/Hidden parent node's windoeNode.index in debug mode (bool)
```
parentIndex
```

Show/Hidden windoeNode.child.len in debug mode (bool)
```
childLen
```

Show/Hidden windoeNode.splitType in debug mode (bool)
```
splitType
```

Show/Hidden whether windoeNode have cursesWindow or not in debug mode (bool)
```
haveCursesWin
```

Show/Hidden windowNode.y in debug mode (bool)
```
y
```

Show/Hidden windowNode.x in debug mode (bool)
```
x
```

Show/Hidden windowNode.h in debug mode (bool)
```
h
```

Show/Hidden windowNode.w in debug mode (bool)
```
w
```

Show/Hidden windowNode.currentLine in debug mode (bool)
```
currentLine
```

Show/Hidden windowNode.currentColumn in debug mode (bool)
```
currentColumn
```

Show/Hidden windowNode.expandedColumn in debug mode (bool)
```
expandedColumn
```

Show/Hidden windowNode.curosr in debug mode (bool)
```
cursor
```

### Debug.EditorView table
Show/Hidden all editorview info in debug mode (bool)
```
enable
```

Show/Hidden editorview.widthOfLineNum in debug mode (bool)
```
widthOfLineNum
```

Show/Hidden editorview.height in debug mode (bool)
```
height
```

Show/Hidden editorview.width in debug mode (bool)
```
width
```

Show/Hidden editorview.originalLine in debug mode (bool)
```
originalLine
```

Show/Hidden editorview.start in debug mode (bool)
```
start
```

Show/Hidden editorview.length in debug mode (bool)
```
length
```

### Debug.BufStatus table

Show/Hidden all bufStatus info in debug mode (bool)
```
enable
```

Show/Hidden bufStatus index in debug mode (bool)
```
bufferIndex
```

Show/Hidden bufStatus.path in debug mode (bool)
```
path
```

Show/Hidden bufStatus.openDir in debug mode (bool)
```
openDir
```

Show/Hidden bufStatus.mode in debug mode (bool)
```
currentMode

```

Show/Hidden bufStatus.prevMode in debug mode (bool)
```
prevMode
```

Show/Hidden bufStatus.language in debug mode (bool)
```
language
```

Show/Hidden bufStatus.characterEncoding in debug mode (bool)
```
encoding 
```

Show/Hidden bufStatus.countChange in debug mode (bool)
```
countChange
```

Show/Hidden bufStatus.cmdLoop in debug mode (bool)
```
cmdLoop
```

Show/Hidden bufStatus.lastSaveTime in debug mode (bool)
```
lastSaveTime
```

Show/Hidden bufStatus.buffer.len in debug mode (bool)
```
bufferLen
```

### Git table

Show/Hidden line changes on sidebars (bool)
```
showChangedLine
```

Interval for updating Git information. (Milli seconds) (integer)
```
1000
```

### SyntaxChecker table

Enable/Disable syntax checker (bool)
```
enable
```

### SmoothScroll table

Enable/Disable Smooth scroll (bool)  
default is true
```
enable
```

Smooth scroll minimum delay (int)  
default is 5
```
minDelay
```

Smooth scroll maximum delay (int)  
default is 20
```
maxDelay
```

### Lsp table

Enable/Disable LSP (bool)  
defaut is `false`
```
enable
```

### Lsp.{languageId} table

File extensions (Array[string])
```
extensions

```

A LSP server command (string)  
```
command
```

Please check more [details](https://github.com/fox0430/moe/blob/develop/documents/lsp.md)

### StartUp.FileOpen table

Display all buffers in multiple views if multiple paths are received when starting the editor (bool)  
The default is `true`
```
autoSplit
```

Setting the split type for `StartUp.FileOpen.autoSplit`. (string)  
`vertical` or `horizontal`  
The default is `vertical`

```
splitType 
```

### Color and theme
moe supports 24 bit color and set in hexadecimal (#000000 ~ #ffffff).
And, `termDefaultBg` and `termDefaultFg`.

Default character color
```
foreground
```
```
background
```

Line number color
```
lineNum
```
```
lineNumBg
```
Current line number highlighting color

```
currentLineNum
```
```
currentLineNumBg
```

Character color of Status line in normal mode
```
statusLineNormalMode
```
```
statusLineNormalModeBg
```

Mode label color in the status line in normal mode
```
statusLineNormalModeLabel
```
```
statusLineNormalModeLabelBg
```

Character color of Status line in normal mode when inactive  
```
statusLineNormalModeInactive
```
```
statusLineNormalModeInactiveBg
```

Character color of Status line in insert mode
```
statusLineInsertMode
```
```
statusLineInsertModeBg
```

Mode label color in the status line in insert mode
```
statusLineInsertModeLabel
```
```
statusLineInsertModeLabelBg
```

Character color of Status line in insert mode when inactive
```
statusLineInsertModeInactive
```
```
statusLineInsertModeInactiveBg
```

Character color of Status line in visual mode
```
statusLineVisualMode
```
```
statusLineVisualModeBg
```

Mode label color in the status line in visual mode
```
statusLineVisualModeLabel
```
```
statusLineVisualModeLabelBg
```

Character color of Status line in visual mode when inactive
```
statusLineVisualModeInactive
```
```
statusLineVisualModeInactiveBg
```

Character color of Status line replace in mode
```
statusLineReplaceMode
```
```
statusLineReplaceModeBg
```

Mode label color in the status line in replace mode
```
statusLineReplaceModeLabel
```
```
statusLineReplaceModeLabelBg
```

Character color of Status line replace in mode when inactive
```
statusLineReplaceModeInactive
```
```
statusLineReplaceModeInactiveBg
```

Character color of Status line in filer mode
```
statusLineFilerMode
```
```
statusLineFilerModeBg
```

Mode label color in the status line in filer mode
```
statusLineFilerModeLabel
```
```
statusLineFilerModeLabelBg
```

Character color of Status line in filer mode when inactive
```
statusLineFilerModeInactive
```
```
statusLineFilerModeInactiveBg
```

Character color of Status line in ex mode
```
statusLineExMode
```
```
statusLineExModeBg
```

Mode label color in the status line in ex mode
```
statusLineExModeLabel
```
```
statusLineExModeLabelBg
```

Character color of Status line in ex mode when inactive
```
statusLineExModeInactive
```
```
statusLineExModeInactiveBg
```

Current git branch text color
```
statusLineGitBranch
```
```
statusLineGitBranchBg
```

Character color of tab title in tab line
```
tab
```
```
tabBg
```

Character color of current tab title in tab line
```
currentTab
```
```
currentTabBg
```

Character color in command bar
```
commandLine
```
```
commandLineBg
```

Character color of error messages
```
errorMessage
```
```
errorMessageBg
```

Character color of warning messages
```
warnMessage
```
```
warnMessageBg
```

Character color of search result highlighting
```
searchResult
```
```
searchResultBg
```

Character color selected in visual mode
```
visualMode
```
```
visualModeBg
```

Syntax highlighting color
```
keyword
```

Syntax highlighting color
```
functionName
```

Syntax highlighting color
```
typeName
```

Syntax highlighting color
```
boolean
```

Syntax highlighting color
```
specialVar
```

Syntax highlighting color
```
builtin
```

Syntax highlighting color
```
charLit
```

Syntax highlighting color
```
stringLit
```

Syntax highlighting color
```
binNumber
```

Syntax highlighting color
```
decNumber
```

Syntax highlighting color
```
floatNumber
```

Syntax highlighting color
```
hexNumber
```

Syntax highlighting color
```
octNumber
```

Syntax highlighting color
```
comment
```

Syntax highlighting color
```
longComment
```

Syntax highlighting color
```
whitespace
```

Syntax highlighting color
```
preprocessor
```

Syntax highlighting color
```
pragma
```

Syntax highlighting color
```
identifier
```

Syntax highlighting color
```
table
```

Syntax highlighting color
```
date
```

Syntax highlighting color
```
operator
```

Character color of current file name in filer mode
```
currentFile
```
```
currentFileBg
```

Character color of file name in filer mode
```
file
```
```
fileBg
```

Character color of directory name in filer mode
```
dir
```
```
dirBg
```

Character color of symbolic links to file in filer mode
```
pcLink
```
```
pcLinkBg
```

Pop-up window text color
```
popUpWindow
```
```
popUpWindowBg
```

Pop-up window current line text color
```
popUpWinCurrentLine
```
```
popUpWinCurrentLineBg
```

Text color when replace text 
```
replaceText
```
```
replaceTextBg
```

Pair of paren highlighting
```
parenPair
```
```
parenPairBg 
```

Current word highlighting
```
currentWord
```
```
currentWordBg
```

Full width space text color
```
highlightFullWidthSpace
```
```
highlightFullWidthSpaceBg
```

Trailing space color
```
highlightTrailingSpaces
```
```
highlightTrailingSpacesBg
```

Reserved word text color
```
reservedWord
```
```
reservedWordBg
```

A info color of Syntax checker result highlighting
```
syntaxCheckInfo
```
```
syntaxCheckInfoBg
```

A hint color of Syntax checker result highlighting
```
syntaxCheckHint
```
```
syntaxCheckHintBg
```

A warning color of Syntax checker result highlighting
```
syntaxCheckWarn
```
```
syntaxCheckWarnBg
```

An error color of Syntax checker result highlighting
```
syntaxCheckErr
```
```
syntaxCheckErrBg
```

Git confict marker color
```
gitConflict
```
```
gitConflictBg
```

Added line color on Diff viewer
```
diffViewerAddedLine 
```
```
diffViewerAddedLineBg
```

Deleted line color on Diff viewer
```
diffViewerDeletedLine
```
```
diffViewerDeletedLineBg
```

Current line color on Backup manager
```
backupManagerCurrentLine
```
```
backupManagerCurrentLineBg 
```

Current line color in configuration mode
```
configModeCurrentLine
```
```
configModeCurrentLineBg
```

Current line background color
```
currentLineBg
```

An added lines sign color of Git in sidebars
```
sidebarGitAddedSign
```
```
sidebarGitAddedSignBg
```

A deleted lines sign color of Git in sidebars
```
sidebarGitDeletedSign
```
```
sidebarGitDeletedSignBg
```

A changed lines sign color of Git in sidebars.
```
sidebarGitChangedSign
```
```
sidebarGitChangedSignBg
```

An info sign color of syntax checker results in sidebars.
```
sidebarSyntaxCheckInfoSign 
```
```
sidebarSyntaxCheckInfoSignBg 
```

A hint sign color of syntax checker results in sidebars.
```
sidebarSyntaxCheckHintSign 
```
```
sidebarSyntaxCheckHintSignBg
```

A warning color of syntax checker results in sidebars.
```
sidebarSyntaxCheckWarnSign 
```
```
sidebarSyntaxCheckWarnSignBg
```

An error color of syntax checker results in sidebars.
```
sidebarSyntaxCheckErrSign 
```
```
sidebarSyntaxCheckErrSignBg
```
