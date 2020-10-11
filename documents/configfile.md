# Configuration file

Write moe's configuration file in toml.  
The location is

```
~/.config/moe/moerc.toml
```

You can use the example -> https://github.com/fox0430/moe/blob/master/example/moerc.toml

## Setting items

### Standard table
Color theme (String)
```"vivid"``` or ```"dark"``` or ```"light"``` or ```"vscode"```  
default is ```"dark"```.
```
theme
```

Note: ```"vscode"``` is you can use current VSCode/VSCodium theme. Check [#648](https://github.com/fox0430/moe/pull/648)

Display line numbers (bool)  
default is true
```
number
```

Display status bar (bool)  
default is true
```
statusBar
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

Set tab width (Integer)  
default is 2
```
tabStop
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

Set cursor shape of the terminal emulator you are using (String) ```"blinkBlock"``` or ```"blinkIbeam"``` or ```noneBlinkBlock``` or ```noneBlinkIbeam```  
default is ```"blinkBlock"```
```
defaultCursor
```

Set cursor shape in normal mode (String) ```"blinkBlock"``` or ```"blinkIbeam"``` or ```noneBlinkBlock``` or ```noneBlinkIbeam```  
default is ```"blinkBlock"```
```
normalModeCursor
```

Set cursor shape in insert mode (String) ```"blinkBlock"``` or ```"blinkIbeam"``` or ```noneBlinkBlock``` or ```noneBlinkIbeam```  
default is ```"blinkIbeam"```

```
insertModeCursor
```

Auto save (bool)  
default is false
```
autoSave
```

Auto save interval (minits) (int)  
default is 5 (5 minits)
```
autoSaveInterval
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
default is true
```
autoDeleteParen
```

Smooth scroll (bool)  
default is true
```
smoothScroll
```

Smooth scroll speed (int)  
default is 15
```
smoothScrollSpeed
```

System clipboard (bool)  
default is true
```
systemClipboard
```

### TabLine table
Show all bufer in tab line (bool)  
default is false  
```
allBuffer
```

### StatusBar table
Multiple status bar (bool)  
default is true
```
multipleStatusBar 
```

Enable/Disable merging status bar with command line (bool)  
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

Show line info (bool)  
default is true
```
line
```

Show column info (bool)  
default is ture
```
column
```

Show character encoding (bool)  
default is true
```
encoding
```

Show language (bool)  
default is true
```
language
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

Show/Hide git branch name in status bar when window is inactive (bool)  
default is false
```
showGitInactive
```

Show/Hide mode string in status bar when window is inactive (bool)  
default is false
```
showModeInactive
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

### WorkSpace table

Enable/Disable workspace bar (bool)  
default is false
```
workSpaceLine
```

### Highlight table

Highlighting any word (array)  

defaut
```
["TODO", "WIP", "NOTE"]
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

```
reservedWord
```

### AutoBackup table

Enable/Disable automatic backups (bool)  
default is ture  
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

If not set, it will be saved in .hisotry in the same directory as the original file.  

default is "" (None)  
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

Enable/disable all messages/notifications in status bar (bool)  
default is true
```
screenNotifications
```

Enable/disable all messages/notifications in log (bool)  
default is true
```
logNotifications
```

Enable/disable auto backups messages/notifications in status bar (bool)  
default is true
```
autoBackupScreenNotify
```

Enable/disable auto backups messages/notifications in log (bool)  
default is true
```
autoBackupLogNotify
```

Enable/disable auto save messages/notifications in status bar (bool)  
default is true
```
autoSaveScreenNotify
```

Enable/disable auto save messages/notifications in log (bool)  
default is true
```
autoSaveLogNotify
```

Enable/disable yank messages/notifications in status bar (bool)  
default is true
```
yankScreenNotify
```

Enable/disable yank messages/notifications in log (bool)  
default is true
```
yankLogNotify
```

Enable/disable delete buffer messages/notifications in status bar (bool)  
default is true
```
deleteScreenNotify
```

Enable/disable delete buffer messages/notifications in log (bool)  
default is true
```
deleteLogNotify
```

Enable/disable save messages/notifications in status bar (bool)  
default is true
```
saveScreenNotify
```

Enable/disable save messages/notifications in log (bool)  
default is true
```
saveLogNotify
```

Enable/disable workspace (create, delete, etc...) messages/notifications in status bar (bool)  
default is true
```
workspaceScreenNotify
```

Enable/disable workspace (create, delete, etc...) messages/notifications in status bar (bool)  
default is true
```
workspaceLogNotify
```

Enable/disable QuickRun messages/notifications in status bar (bool)  
default is true
```
quickRunScreenNotify
```

Enable/disable QuickRun messages/notifications in log (bool)  
default is true
```
quickRunLogNotify
```

Enable/disable build on save messages/notifications in status bar (bool)  
default is true
```
buildOnSaveScreenNotify
```

Enable/disable build on save messages/notifications in log (bool)  
default is true
```
buildOnSaveLogNotify
```

Enable/disable filer messages/notifications in status bar (bool)  
default is true
```
filerScreenNotify
```

Enable/disable filer messages/notifications in log (bool)  
default is true
```
filerLogNotify
```

Enable/disable restore messages/notifications in status bar (bool)  
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

### Debug.WorkSpace table

Show/Hidden all WorkSpace info in debug mode (bool)
```
enable
```

Show/Hidden the number of workspaces in debug mode (bool)
```
numOfWorkSpaces
```

Show/Hidden status.currentWorkSpaceIndex in debug mode (bool)
```
currentWorkSpaceIndex 
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

### Color and theme
-- Available colors --

default  
black  
maroon  
green  
olive  
navy  
purple_1  
teal  
silver  
gray  
red  
lime  
yellow  
blue  
fuchsia  
aqua  
white  
gray0  
navyBlue  
darkBlue  
blue3_1  
blue3_2  
blue1  
darkGreen  
deepSkyBlue4_1  
deepSkyBlue4_2  
deepSkyBlue4_3  
dodgerBlue3_1  
dodgerBlue3_2  
green4  
springGreen4  
turquoise4  
deepSkyBlue3_1  
deepSkyBlue3_2  
dodgerBlue1  
green3_1  
springGreen3_1  
darkCyan  
lightSeaGreen  
deepSkyBlue2  
deepSkyBlue1  
green3_2  
springGreen3_3  
springGreen2_1  
cyan3  
darkTurquoise  
turquoise2  
green1  
springGreen2_2  
springGreen1  
mediumSpringGreen  
cyan2  
cyan1  
darkRed_1  
deepPink4_1  
purple4_1  
purple4_2  
purple3  
blueViolet  
orange4_1  
gray37  
mediumPurple4  
slateBlue3_1  
slateBlue3_2  
royalBlue1  
chartreuse4  
darkSeaGreen4_1  
paleTurquoise4  
steelBlue  
steelBlue3  
cornflowerBlue  
chartreuse3_1  
darkSeaGreen4_2  
cadetBlue_1  
cadetBlue_2  
skyBlue3  
steelBlue1_1  
chartreuse3_2  
paleGreen3_1  
seaGreen3  
aquamarine3  
mediumTurquoise  
steelBlue1_2  
chartreuse2_1  
seaGreen2  
seaGreen1_1  
seaGreen1_2  
aquamarine1_1  
darkSlateGray2  
darkRed_2  
deepPink4_2  
darkMagenta_1  
darkMagenta_2  
darkViolet_1  
purple_2  
orange4_2  
lightPink4  
plum4  
mediumPurple3_1  
mediumPurple3_2  
slateBlue1  
yellow4_1  
wheat4  
gray53  
lightSlategray  
mediumPurple  
lightSlateBlue  
yellow4_2  
Wheat4  
darkSeaGreen  
lightSkyBlue3_1  
lightSkyBlue3_2  
skyBlue2  
chartreuse2_2  
darkOliveGreen3_1  
paleGreen3_2  
darkSeaGreen3_1  
darkSlateGray3  
skyBlue1  
chartreuse1  
lightGreen_1  
lightGreen_2  
paleGreen1_1  
aquamarine1_2  
darkSlateGray1  
red3_1  
deepPink4  
mediumVioletRed  
magenta3  
darkViolet_2  
purple  
darkOrange3_1  
indianRed_1  
hotPink3_1  
mediumOrchid3  
mediumOrchid  
mediumPurple2_1  
darkGoldenrod  
lightSalmon3_1  
rosyBrown  
gray63  
mediumPurple2_2  
mediumPurple1  
gold3_1  
darkKhaki  
navajoWhite3  
gray69  
lightSteelBlue3  
lightSteelBlue  
yellow3_1  
darkOliveGreen3_2  
darkSeaGreen3_2  
darkSeaGreen2_1  
lightCyan3  
lightSkyBlue1  
greenYellow  
darkOliveGreen2  
paleGreen1_2  
darkSeaGreen2_2  
darkSeaGreen1_1  
paleTurquoise1  
red3_2  
deepPink3_1  
deepPink3_2  
magenta3_1  
magenta3_2  
magenta2_1  
darkOrange3_2  
indianRed_2  
hotPink3_2  
hotPink2  
orchid  
mediumOrchid1_1  
orange3  
lightSalmon3_2  
lightPink3  
pink3  
plum3  
violet  
gold3_2  
lightGoldenrod3  
tan  
mistyRose3  
thistle3  
plum2  
yellow3_2  
khaki3  
lightGoldenrod2  
lightYellow3  
gray84  
lightSteelBlue1  
yellow2  
darkOliveGreen1_1  
darkOliveGreen1_2  
darkSeaGreen1_2  
honeydew2  
lightCyan1  
red1  
deepPink2  
deepPink1_1  
deepPink1_2  
magenta2_2  
magenta1  
orangeRed1  
indianRed1_1  
indianRed1_2  
hotPink1_1  
hotPink1_2  
mediumOrchid1_2  
darkOrange  
salmon1  
lightCoral  
paleVioletRed1  
orchid2  
orchid1  
orange1  
sandyBrown  
lightSalmon1  
lightPink1  
pink1  
plum1  
gold1  
lightGoldenrod2_1  
lightGoldenrod2_2  
navajoWhite1  
mistyRose1  
thistle1  
yellow1  
lightGoldenrod1  
khaki1  
wheat1  
cornsilk1  
gray100  
gray3  
gray7  
gray11  
gray15  
gray19  
gray23  
gray27  
gray30  
gray35  
gray39  
gray42  
gray46  
gray50  
gray54  
gray58  
gray62  
gray66  
gray70  
gray74  
gray78  
gray82  
gray85  
gray89  
gray93  

-- Color Srttings --

Background color
```
editorBg
```

Line number color
```
lineNum
```

Line number background color
```
lineNumBg
```
Current line number highlighting color

```
currentLineNum
```

Current line number highlighting background color
```
currentLineNumBg
```

Character color of Status bar in normal mode
```
statusBarNormalMode
```

Status bar base color in normal mode
```
statusBarNormalModeBg
```

Mode text color in the status bar in normal mode
```
statusBarModeNormalMode
```

Background color of mode text in the status bar in normal mode
```
statusBarModeNormalModeBg
```

Character color of Status bar in normal mode when inactive  
```
statusBarNormalModeInactive
```

Status bar base color in normal mode when inactive  
```
statusBarNormalModeInactiveBg
```

Character color of Status bar in insert mode
```
statusBarInsertMode
```

Status bar base color in insert mode
```
statusBarInsertModeBg
```

Mode text color in the status bar in insert mode
```
statusBarModeInsertMode
```

Background color of mode text in the status bar in insert mode
```
statusBarModeInsertModeBg
```

Character color of Status bar in insert mode when inactive
```
statusBarInsertModeInactive
```

Status bar base color in insert mode when inactive
```
statusBarInsertModeInactiveBg
```

Character color of Status bar in visual mode
```
statusBarVisualMode
```

Status bar base color in visual mode
```
statusBarVisualModeBg
```

Mode text color in the status bar in visual mode
```
statusBarModeVisualMode
```

Background color of mode text in the status bar in visual mode
```
statusBarModeVisualModeBg
```

Character color of Status bar in visual mode when inactive
```
statusBarVisualModeInactive
```

Status bar base color in visual mode when inactive
```
statusBarVisualModeInactiveBg
```

Character color of Status bar replace in mode
```
statusBarReplaceMode
```

Status bar base color in replace mode
```
statusBarReplaceModeBg
```

Mode text color in the status bar in replace mode
```
statusBarModeReplaceMode
```

Background color of mode text in the status bar in replace mode
```
statusBarModeReplaceModeBg
```

Character color of Status bar replace in mode when inactive
```
statusBarReplaceModeInactive
```

Status bar base color in replace mode when inactive
```
statusBarReplaceModeInactiveBg
```

Character color of Status bar in filer mode
```
statusBarFilerMode
```

Status bar base color in filer mode
```
statusBarFilerModeBg
```

Mode text color in the status bar in filer mode
```
statusBarModeFilerMode
```

Background color of mode text in the status bar in filer mode
```
statusBarModeFilerModeBg
```

Character color of Status bar in filer mode when inactive
```
statusBarFilerModeInactive
```

Status bar base color in filer mode when inactive
```
statusBarFilerModeInactiveBg
```

Character color of Status bar in ex mode
```
statusBarExMode
```

Status bar base color in ex mode
```
statusBarExModeBg
```

Mode text color in the status bar in ex mode
```
statusBarExModeBg
```

Background color of mode text in the status bar in ex mode
```
statusBarModeExModeBg
```

Character color of Status bar in ex mode when inactive
```
statusBarExModeInactive
```

Status bar base color in ex mode when inactive
```
statusBarExModeInactiveBg
```

Current git branch text color
```
statusBarGitBranch

```

Current git branch background color
```
statusBarGitBranchBg
```


Character color of tab title in tab line
```
tab
```

Background color of tab title in tab line
```
tabBg
```

Character color of current tab title in tab line
```
currentTab
```

Background color of current tab title in tab line
```
currentTabBg
```

Character color in command bar
```
commandBar
```

Background color in command bar
```
commandBarBg
```

Character color of error messages
```
errorMessage
```

Background color of error messages
```
errorMessageBg
```

Character color of search result highlighting
```
searchResult
```

Background color of search result highlighting
```
searchResultBg
```

Character color selected in visual mode
```
visualMode
```

Background color selected in visual mode
```
visualModeBg
```

Default text color
```
defaultCharactorColor
```

Syntax highlighting color
```
gtKeyword
```

Syntax highlighting color
```
gtFunctionName
```

Syntax highlighting color
```
gtBoolean
```

Syntax highlighting color
```
gtSpecialVar
```

Syntax highlighting color
```
gtBuiltin
```

Syntax highlighting color
```
gtStringLit
```

Syntax highlighting color
```
gtDecNumber
```

Syntax highlighting color
```
gtComment
```

Syntax highlighting color
```
gtLongComment
```

Syntax highlighting color
```
gtWhitespace
```

Syntax highlighting color
```
gtPreprocessor
```

Character color of current file name in filer mode
```
currentFile
```

Background color of current file name in filer mode
```
currentFileBg
```

Character color of file name in filer mode
```
file
```

Background color of file name in filer mode
```
fileBg
```

Character color of directory name in filer mode
```
dir
```

Background color of directory name in filer mode
```
dirBg
```
Character color of symbolic links to file in filer mode
```
pcLink
```

Background color of symbolic links to file in filer mode
```
pcLinkBg
```

Pop-up window text color
```
popUpWindow
```

Pop-up window background color
```
popUpWindowBg
```

Pop-up window current line text color
```
popUpWinCurrentLine
```

Pop-up window current line background color
```
popUpWinCurrentLineBg
```

Text color when replace text 
```
replaceText
```

Background color when replace text 
```
replaceTextBg
```

Background color of current word
```
currentWordBg
```

Full width space text color
```
highlightFullWidthSpace
```

Full width space background color
```
highlightFullWidthSpaceBg
```

Trailing space color
```
highlightTrailingSpaces
```

Trailing space background color
```
highlightTrailingSpacesBg
```

Workspace bar text color
```
workSpaceBar
```

Workspace bar background color
```
workSpaceBarBg
```

Reserved word text color
```
reservedWord
```

Reserved word background color
```
reservedWordBg
```

Current line color in configuration mode
```
currentSetting
```

Current line background color in configuration mode
```
currentSettingBg
```
