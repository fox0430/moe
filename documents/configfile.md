# Configuration file

Write moe's configuration file in toml.  
The location is

```
~/.config/moe/moerc.toml
```

You can use the example -> https://github.com/fox0430/moe/blob/develop/example

## Configuration Items

### CursorShape

- type: string

| Name |
|:-----------------------------|
| terminalDefault |
| blinkBlock |
| blinkIbeam |
| noneBlinkBlock |
| noneBlinkIbeam |


### TerminalColorMode

- type: string

| Name |
|:-----------------------------|
| none |
| 8 |
| 16 |
| 256 |
| 24bit |


### ClipbloardTool

- type: string

| Name |
|:-----------------------------|
| xsel |
| xclip |
| wl-clipboard |
| wsl-default |
| macOS-default |


### StatusLineItem

- type: string

| Name |
|:-----------------------------|
| lineNumber |
| totalLines |
| columnNumber |
| totalColumns |
| encoding |
| fileType |
| fileTypeIcon |


### ThemeKind

- type: string

| Name | Description |
|:-----------------------------|:-----------------------------|
| default | The default theme |
| vscode | VSCode theme |
| config | User theme. Also please set `Theme.path` |

### Standard table

| Name | Type | Default Value | Description |
|:-----------------------------|:-----------------------------|:---------------------------|:---------------------------|
| number | bool | true | Display line numbers |
| statusLine | bool | true | Display status lines |
| syntax | bool | true | Enable syntax highlighting |
| indentationLines | bool | true | Enable indentation lines |
| tabStop | integer | 2 | Tab width |
| sidebar | bool | true | Enable Sidebars for editor views |
| ignorecase | bool | true | Enable ignorecase when searching |
| smartcase | bool | true | Enable semartcase when searching |
| autoCloseParen | bool | true | Automatic closing brackets |
| autoDeleteParen | bool | | Automatic delete brackets |
| autoIndent | bool | true | Automatic indentation |
| disableChangeCursor | bool | false | Disable change of the cursor shape |
| defaultCursor | CursorShape | terminalDefault | The cursor shape of the terminal emulator you are using |
| normalModeCursor | CursorShape |terminalDefault | The cursor shape in Normal mode |
| insertModeCursor | CursorShape | blinkIbeam | The cursor shape in insert mode |
| liveReloadOfConf | bool | false | Enable live reload of the configuration file |
| liveReloadOfFile | bool | false | Enable live reload of opening files |
| incrementalSearch | bool | false | Enable incremental search |
| popUpWindowInExmode | bool | true | Show Pop-up window in Ex mode |
| colorMode | TerminalColorMode | 24bit | Terminal color mode |


### Clipboard table

| Name | Type | Default Value | Description |
|:-----------------------------|:-----------------------------|:---------------------------|:---------------------------|
| enable | bool | true | Enable system clipboard |
| tool | ClipbloardTool | xsel | The clipboard tool for Linux |


### TabLine table

| Name | Type | Default Value | Description |
|:-----------------------------|:-----------------------------|:---------------------------|:---------------------------|
| allBuffer | bool | false | Display all buffer in tab line |


### StatusLine table

| Name | Type | Default Value | Description |
|:-----------------------------|:-----------------------------|:---------------------------|:---------------------------|
| multipleStatusLine | bool | true | Show multiple status lines |
| merge | bool | fale | Enable merge the status line with the command line |
| mode | bool | true | Display the current mode |
| chanedMark | bool | true | Display the buffer changed mark |
| directory | bool | true | Display the directory of the path |
| gitbranchName | bool | true | Display the current git branch name |
| showChangedLine | bool | true | Display number of changed lines |
| showGitInactive | bool | false | Display the git branch name on the status line in inactive windows |
| showModeInactive | bool | false | Display the mode on the status line in inactive windows |
| setupText | string | {lineNumber}/{totalLines} {columnNumber}/{totalColumns} {encoding} {fileType} | Text to customize the items displayed in the status line. Please check StatusLineItem |


### BuildOnSave table

| Name | Type | Default Value | Description |
|:-----------------------------|:-----------------------------|:---------------------------|:---------------------------|
| buildOnSave | bool | false | Enable build on save |
| workspaceRoot | string | | Project root directory |
| command | string | | Override commands executed at build |


### Highlight table

| Name | Type | Default Value | Description |
|:-----------------------------|:-----------------------------|:---------------------------|:---------------------------|
| currentLine | bool | true | Highlight the current line background |
| reservedWord | Array of string | ["TODO", "WIP", "NOTE"] | Highlight any words |
| replaceText | bool | true | Highlight replacement text |
| pairOfParen | bool | true | Highlight a pair of brackets |
| fullWidthSpace | bool | true | Highlight full-width spaces |
| trailingSpaces | bool | true | Highlight trailing spaces |
| currentWord | bool | true | Highlight other uses of the current word under the cursor |


### AutoBackup table

| Name | Type | Default Value | Description |
|:-----------------------------|:-----------------------------|:---------------------------|:---------------------------|
| enable | bool | false | Enable automatic backups |
| idleTime | integer | 10 | Start backup when there is no operation times (seconds) |
| interval | integer | 5 | Backup interval (minutes) |
| backupDir | string | ~/.cache/moe/backups | Directory to save backup files |
| dirToExclude | Array of string | ["/etc"] | Exclude dirs for where you don't want to produce automatic backups |


### QuickRun table

| Name | Type | Default Value | Description |
|:-----------------------------|:-----------------------------|:---------------------------|:---------------------------|
| saveBufferWhenQuickRun | bool | true | Save buffer when run QuickRun |
| command | string | | Commands to be executed by quick run |
| timeout | integer | 30 | Command timeout (seconds) |
| nimAdvancedCommand | string | c | Nim compiler advanced args |
| clangOptions | string | | C lang compileer options. The default compiler is gcc  |
| cppOptions | string | | C++ compiler options. The default compiler is gcc |
| nimOptions | string | | Nim compiler options |
| shOptions | string | | sh options |
| bashOptions | string | | bash options |


### Notification table

| Name | Type | Default Value | Description |
|:-----------------------------|:-----------------------------|:---------------------------|:---------------------------|
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
| saveLogNotify | bool | true | Save messages/notifications to the log (bool) |
| quickRunScreenNotify | bool | true | QuickRun messages/notifications in the command line |
| quickRunLogNotify | bool | true | QuickRun messages/notifications to the log |
| buildOnSaveScreenNotify | bool | true | Build on save messages/notifications in the command line |
| buildOnSaveLogNotify | bool | true | Build on save messages/notifications to the log |
| filerScreenNotify | bool | true | Filer messages/notifications in the command line |
| filerLogNotify | bool | true | Filer messages/notifications to the log |
| restoreScreenNotify | bool | true | Restore messages/notifications in the command line |
| restoreLogNotify | bool | true | Restore messages/notifications to the log |


### Filer table

| Name | Type | Default Value | Description |
|:-----------------------------|:-----------------------------|:---------------------------|:---------------------------|
| showIcons | bool | true | Show/Hidden file type icons |


### Autocomplete table

| Name | Type | Default Value | Description |
|:-----------------------------|:-----------------------------|:---------------------------|:---------------------------|
| enable | bool | true | General-purpose autocompletion |


### AutoSave table

| Name | Type | Default Value | Description |
|:-----------------------------|:-----------------------------|:---------------------------|:---------------------------|
| enable | bool | true | Auto save |
| interval | integer | 5 | Auto save interval (Minits) |


### Persist table

| Name | Type | Default Value | Description |
|:-----------------------------|:-----------------------------|:---------------------------|:---------------------------|
| exCommand | bool | true | Saving Ex command history |
| exCommandHistoryLimit | integer | 1000 | The maximum entries of Ex command history to save |
| search | bool | true | Saving search history |
| searchHistoryLimit | integer | 1000 | The maximum entries of search history to save |
| curosrPosition | bool | true | Saving last cursor position |


### Debug.WindowNode table

| Name | Type | Default Value | Description |
|:-----------------------------|:-----------------------------|:---------------------------|:---------------------------|
| enable | bool | true | All WindowNode info |
| currentWindow | bool | true | Whether the current window or not |
| index | bool | true | WindowNode.index |
| windowIndex | bool | true | WindowNode.windowIndex |
| bufferIndex | bool | true | WindowNode.bufferIndex |
| parentIndex | bool | true | Parent node's WindoeNode.index |
| childLen | bool | true | WindoeNode.child.len |
| splitType | bool | true | WindoeNode.splitType |
| haveCursesWin | bool | true | Whether windoeNode have cursesWindow or not |
| y | bool | true | WindowNode.y |
| x | bool | true | WindowNode.x |
| h | bool | true | WindowNode.h |
| w | bool | true | WindowNode.w |
| currentLine | bool | true | WindowNode.currentLine |
| currentColumn | bool | true | WindowNode.currentColumn |
| expandedColumn | bool | true | WindowNode.expandedColumn |
| cursor | bool | true | WindowNode.curosr |


### Debug.EditorView table

| Name | Type | Default Value | Description |
|:-----------------------------|:-----------------------------|:---------------------------|:---------------------------|
| enable | bool | true | All Editorview info |
| widthOfLineNum | bool | true | Editorview.widthOfLineNum |
| height | bool | true | Editorview.height |
| width | bool | true | Editorview.width |
| originalLine | bool | true | Editorview.originalLine |
| start | bool | true | Editorview.start |
| length | bool | true | Editorview.length |

### Debug.BufStatus table

| Name | Type | Default Value | Description |
|:-----------------------------|:-----------------------------|:---------------------------|:---------------------------|
| enable | bool | true | All BufStatus info |
| bufferIndex | bool | true | The index of BufStatus |
| path | bool | true | BufStatus.path |
| openDir | bool | true | BufStatus.openDir |
| currentMode | bool | true | BufStatus.mode |
| prevMode | bool | true | BufStatus.prevMode  |
| language | bool | true | BufStatus.language |
| encoding | bool | true | BufStatus.characterEncoding  |
| countChange | bool | true | BufStatus.countChange  |
| cmdLoop | bool | true | BufStatus.cmdLoop  |
| lastSaveTime | bool | true | BufStatus.lastSaveTime  |
| bufferLen | bool | true | BufStatus.buffer.len |


### Git table

| Name | Type | Default Value | Description |
|:-----------------------------|:-----------------------------|:---------------------------|:---------------------------|
| showChangedLine | bool | true | Line changes on sidebars |
| updateInterval | integer | 1000 | Interval for updating Git information. (Milli seconds) |


### SyntaxChecker table

| Name | Type | Default Value | Description |
|:-----------------------------|:-----------------------------|:---------------------------|:---------------------------|
| enable | bool | true | Syntax checker |


### SmoothScroll table

| Name | Type | Default Value | Description |
|:-----------------------------|:-----------------------------|:---------------------------|:---------------------------|
| enable | bool | true | Smooth scroll |
| minDelay | integer | 5 | Minimum delay |
| maxDelay | integer | 20 | Maximum delay |


### Lsp table

| Name | Type | Default Value | Description |
|:-----------------------------|:-----------------------------|:---------------------------|:---------------------------|
| enable | bool | true | LSP (Language Server Protocol) Client |


### Lsp.Completion table

| Name | Type | Default Value | Description |
|:-----------------------------|:-----------------------------|:---------------------------|:---------------------------|
| enable | bool | true | LSP Completion |


### Lsp.Declaration table

| Name | Type | Default Value | Description |
|:-----------------------------|:-----------------------------|:---------------------------|:---------------------------|
| enable | bool | true | LSP Goto Declaration |


### Lsp.Definition table

| Name | Type | Default Value | Description |
|:-----------------------------|:-----------------------------|:---------------------------|:---------------------------|
| enable | bool | true | LSP Goto Definition |


### Lsp.TypeDefinition table

| Name | Type | Default Value | Description |
|:-----------------------------|:-----------------------------|:---------------------------|:---------------------------|
| enable | bool | true | LSP TypeDefinition |


### Lsp.Implementation table

| Name | Type | Default Value | Description |
|:-----------------------------|:-----------------------------|:---------------------------|:---------------------------|
| enable | bool | true | LSP Implementation |


### Lsp.Diagnostics table

| Name | Type | Default Value | Description |
|:-----------------------------|:-----------------------------|:---------------------------|:---------------------------|
| enable | bool | true | LSP Diagnostics |


### Lsp.Hover table

| Name | Type | Default Value | Description |
|:-----------------------------|:-----------------------------|:---------------------------|:---------------------------|
| enable | bool | true | LSP Hover |


### Lsp.InlayHint table

| Name | Type | Default Value | Description |
|:-----------------------------|:-----------------------------|:---------------------------|:---------------------------|
| enable | bool | true | LSP InlayHint |


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
| enable | bool | true | LSP Code Lens |


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


### Lsp.{languageId} table

| Name | Type | Default Value | Description |
|:-----------------------------|:-----------------------------|:---------------------------|:---------------------------|
| extensions | Array of string | | File extensions |
| command | string | | LSP server command |
| rustAnalyzerRunSingle | bool | true | `rust-analyzer.runSingle`. Only effective with rust-analyzer and if `Lsp.CodeLens` is enabled. |
| rustAnalyzerDebugSingle | bool | true | `rust-analyzer.debugSingle`. Only effective with rust-analyzer and if `Lsp.CodeLens` is enabled. |


Please check more [details](https://github.com/fox0430/moe/blob/develop/documents/lsp.md)

### StartUp.FileOpen table

| Name | Type | Default Value | Description |
|:-----------------------------|:-----------------------------|:---------------------------|:---------------------------|
| autoSplit | bool | true | Display all buffers in multiple views if multiple paths are received when starting the editor |
| splitType | string | vertical | The split type for `StartUp.FileOpen.autoSplit` |


### Theme table
| Name | Type | Default Value | Description |
|:-----------------------------|:-----------------------------|:---------------------------|:---------------------------|
| kind | ThemeKind | default | Theme kind |
| path | string | | A path of user theme. Also Please set `"config"` to `Theme.kind`. |


### Color table (Theme)
Put the toml file that describes the `Colors` table in the path specified by `Theme.path` in `moerc.toml`.

moe supports 24 bit color and set in hexadecimal (`#000000` ~ `#ffffff`).
And, `termDefaultBg` and `termDefaultFg`.

| Name |  Description |
|:-----------------------------|:-----------------------------|
| foreground | Default text color |
| background | Default background olor |
| currentLineBg | Background color of the editor current line |
| lineNum | Text color of line numbers  |
| lineNumBg | Background color of line numbers |
| currentLineNum | Text color of current line number highlighting |
| currentLineNumBg | Background color of current line number highlighting |
| statusLineNormalMode | Text color of Status line in Normal mode |
| statusLineNormalModeBg | Background color of Status line in Normal mode |
| statusLineNormalModeLabel | Mode label text color in status line in Normal mode |
| statusLineNormalModeLabelBg | Mode label background color in status line in Normal mode |
| statusLineNormalModeInactive | Text color of status line in Normal mode when inactive |
| statusLineNormalModeInactiveBg | Background color of status line in Normal mode when inactive |
| statusLineInsertMode | Text color of status line in Insert mode |
| statusLineInsertModeBg | Background color of status line in Insert mode |
| statusLineInsertModeLabel | Mode label text color in status line in Insert mode |
| statusLineInsertModeLabelBg | Mode label background color in status line in Insert mode |
| statusLineInsertModeInactive | Text color of status line in Insert mode when inactive |
| statusLineInsertModeInactiveBg | Background color of status line in Insert mode when inactive |
| statusLineVisualMode | Text color of Status line in Visual mode |
| statusLineVisualModeBg | Background color of Status line in Visual mode |
| statusLineVisualModeLabel | Mode label text color in status line in visual mode |
| statusLineVisualModeLabelBg | Mode label background color in status line in visual mode |
| statusLineVisualModeInactive | Text color of Status line in Visual mode when inactive |
| statusLineVisualModeInactiveBg | Background color of status line in Visual mode when inactive |
| statusLineReplaceMode | Text color of Status line Replace in mode |
| statusLineReplaceModeBg | Background color of status line Replace in mode |
| statusLineReplaceModeLabel | Mode label text color in status line in Replace mode |
| statusLineReplaceModeLabelBg | Mode label background color in status line in Replace mode |
| statusLineReplaceModeInactive | Text color of Status line Replace in mode when inactive |
| statusLineReplaceModeInactiveBg | Background color of Status line Replace in mode when inactive |
| statusLineFilerMode | Text color of Status line in Filer mode |
| statusLineFilerModeBg | Background color of Status line in Filer mode |
| statusLineFilerModeLabel | Mode label text color in status line in Filer mode |
| statusLineFilerModeLabelBg | Mode label background color in status line in Filer mode |
| statusLineFilerModeInactive | Text color of status line in Filer mode when inactive |
| statusLineFilerModeInactiveBg | Background color of Status line in Filer mode when inactive |
| statusLineExMode | Text color of Status line in Ex mode |
| statusLineExModeBg | Background color of Status line in Ex mode |
| statusLineExModeLabel | Mode label text color in status line in Ex mode |
| statusLineExModeLabelBg | Mode label background color in status line in Ex mode |
| statusLineExModeInactive | Text color of status line in Ex mode when inactive |
| statusLineExModeInactiveBg | Background color of Status line in Ex mode when inactive |
| statusLineGitBranch | Text color of git branch |
| statusLineGitBranchBg | Background color of git branch |
| tab | Text color of tab title in tab line |
| tabBg | Background color of tab title in tab line |
| currentTab | Text color of current tab title in tab line |
| currentTabBg | Background color of current tab title in tab line |
| commandLine | Text color in command line |
| commandLineBg | Background color in command line |
| errorMessage | Text color of error messages |
| errorMessageBg | Background color of error messages |
| warnMessage | Text color of warning messages |
| warnMessageBg | Background color of warning messages |
| searchResult | Text color of search result highlighting |
| searchResultBg | Background color of search result highlighting |
| selectArea | Text color selected in visual mode |
| selectAreaBg | Background color selected in visual mode |
| keyword | Syntax highlighting color |
| functionName | Syntax highlighting color |
| typeName | Syntax highlighting color |
| boolean | Syntax highlighting color |
| specialVar | Syntax highlighting color |
| builtin | Syntax highlighting color |
| charLit | Syntax highlighting color |
| stringLit | Syntax highlighting color |
| binNumber | Syntax highlighting color |
| decNumber | Syntax highlighting color |
| floatNumber | Syntax highlighting color |
| hexNumber | Syntax highlighting color |
| octNumber | Syntax highlighting color |
| comment | Syntax highlighting color |
| longComment | Syntax highlighting color |
| whitespace | Syntax highlighting color |
| preprocessor | Syntax highlighting color |
| pragma | Syntax highlighting color |
| identifier | Syntax highlighting color |
| table | Syntax highlighting color |
| date | Syntax highlighting color |
| operator | Syntax highlighting color |
| enumMember | Syntax highlighting color (LSP Semantic Tokens) |
| interfaceName | Syntax highlighting color (LSP Semantic Tokens) |
| typeParameter | Syntax highlighting color (LSP Semantic Tokens) |
| parameter | Syntax highlighting color (LSP Semantic Tokens) |
| variable | Syntax highlighting color (LSP Semantic Tokens) |
| property | Syntax highlighting color (LSP Semantic Tokens) |
| string | Syntax highlighting color (LSP Semantic Tokens) |
| event | Syntax highlighting color (LSP Semantic Tokens) |
| function | Syntax highlighting color (LSP Semantic Tokens) |
| method | Syntax highlighting color (LSP Semantic Tokens) |
| macro | Syntax highlighting color (LSP Semantic Tokens) |
| regexp | Syntax highlighting color (LSP Semantic Tokens) |
| decorator | Syntax highlighting color (LSP Semantic Tokens) |
| angle | Syntax highlighting color (LSP Semantic Tokens) |
| arithmetic | Syntax highlighting color (LSP Semantic Tokens) |
| attribute | Syntax highlighting color (LSP Semantic Tokens) |
| attributeBracket | Syntax highlighting color (LSP Semantic Tokens) |
| bitwise | Syntax highlighting color (LSP Semantic Tokens) |
| brace | Syntax highlighting color (LSP Semantic Tokens) |
| bracket | Syntax highlighting color (LSP Semantic Tokens) |
| builtinAttribute | Syntax highlighting color (LSP Semantic Tokens) |
| builtinType | Syntax highlighting color (LSP Semantic Tokens) |
| colon | Syntax highlighting color (LSP Semantic Tokens) |
| comma | Syntax highlighting color (LSP Semantic Tokens) |
| comparison | Syntax highlighting color (LSP Semantic Tokens) |
| constParameter | Syntax highlighting color (LSP Semantic Tokens) |
| derive | Syntax highlighting color (LSP Semantic Tokens) |
| deriveHelper | Syntax highlighting color (LSP Semantic Tokens) |
| dot | Syntax highlighting color (LSP Semantic Tokens) |
| escapeSequence | Syntax highlighting color (LSP Semantic Tokens) |
| invalidEscapeSequence | Syntax highlighting color (LSP Semantic Tokens) |
| formatSpecifier | Syntax highlighting color (LSP Semantic Tokens) |
| generic | Syntax highlighting color (LSP Semantic Tokens) |
| label | Syntax highlighting color (LSP Semantic Tokens) |
| lifetime | Syntax highlighting color (LSP Semantic Tokens) |
| logical | Syntax highlighting color (LSP Semantic Tokens) |
| macroBang | Syntax highlighting color (LSP Semantic Tokens) |
| parenthesis | Syntax highlighting color (LSP Semantic Tokens) |
| punctuation | Syntax highlighting color |
| selfKeyword | Syntax highlighting color (LSP Semantic Tokens) |
| selfTypeKeyword | Syntax highlighting color (LSP Semantic Tokens) |
| semicolon | Syntax highlighting color (LSP Semantic Tokens) |
| typeAlias | Syntax highlighting color (LSP Semantic Tokens) |
| toolModule | Syntax highlighting color (LSP Semantic Tokens) |
| union | Syntax highlighting color (LSP Semantic Tokens) |
| unresolvedReference | Syntax highlighting color (LSP Semantic Tokens) |
| currentFile | Text color of current file name in Filer mode |
| file | Text color of file name in Filer mode |
| fileBg | Background color of file name in Filer mode |
| dir | Text of directory name in filer mode |
| dirBg | Background of directory name in filer mode |
| pcLink | Text of symbolic links to file in filer mode |
| pcLinkBg | Background of symbolic links to file in filer mode |
| popUpWindow | Pop-up window text color |
| popUpWindowBg | Pop-up window background color |
| popUpWinCurrentLine | Pop-up window current line text color |
| popUpWinCurrentLineBg | Pop-up window current line background color |
| replaceText | Text color of replacing text |
| replaceTextBg | Background color of replacing text |
| parenPair | Pair of bracket highlighting |
| parenPairBg | Pair of bracket highlighting |
| currentWord | Current word highlighting |
| currentWordBg | Current word highlighting |
| highlightFullWidthSpace | Full-width space color |
| highlightTrailingSpaces | Trailing space color |
| reservedWord | Reserved word text color |
| reservedWordBg | Reserved word text color |
| syntaxCheckInfo | A info color of syntax checker result highlighting |
| syntaxCheckInfoBg | A info color of syntax checker result highlighting |
| syntaxCheckHint | A hint color of syntax checker result highlighting |
| syntaxCheckHintBg | A hint color of syntax checker result highlighting |
| syntaxCheckWarn | A warning color of syntax checker result highlighting |
| syntaxCheckWarnBg | A warning color of syntax checker result highlighting |
| syntaxCheckErr | An error color of syntax checker result highlighting |
| syntaxCheckErrBg | An error color of syntax checker result highlighting |
| gitConflict | Git conflict marker color |
| gitConflictBg | Git conflict marker color |
| diffViewerAddedLine  | Added line color on Diff viewer |
| diffViewerAddedLineBg  | Added line color on Diff viewer |
| diffViewerDeletedLine | Deleted line color on Diff viewer |
| diffViewerDeletedLineBg | Deleted line color on Diff viewer |
| backupManagerCurrentLine | Current line color on Backup manager |
| backupManagerCurrentLineBg | Current line color on Backup manager |
| configModeCurrentLine | Current line color in Configuration mode |
| configModeCurrentLineBg | Current line color in Configuration mode |
| sidebarGitAddedSign | An added lines sign color of Git in sidebars |
| sidebarGitAddedSignBg | An added lines sign color of Git in sidebars |
| sidebarGitDeletedSign | A deleted lines sign color of Git in sidebars |
| sidebarGitDeletedSignBg | A deleted lines sign color of Git in sidebars |
| sidebarGitChangedSign | A changed lines sign color of Git in sidebars |
| sidebarGitChangedSignBg | A changed lines sign color of Git in sidebars |
| sidebarSyntaxCheckInfoSign  | A info sign color of syntax checker results in sidebars |
| sidebarSyntaxCheckInfoSignBg  | A info sign color of syntax checker results in sidebars |
| sidebarSyntaxCheckHintSign | A hint sign color of syntax checker results in sidebars |
| sidebarSyntaxCheckHintSignBg | A hint sign color of syntax checker results in sidebars |
| sidebarSyntaxCheckWarnSign | A warning color of syntax checker results in sidebars |
| sidebarSyntaxCheckWarnSignBg | A warning color of syntax checker results in sidebars |
| sidebarSyntaxCheckErrSign | An error color of syntax checker results in sidebars |
| sidebarSyntaxCheckErrSignBg | An error color of syntax checker results in sidebars |
