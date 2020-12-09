import terminal
import editorstatus, bufferstatus, ui, movement, unicodetext, gapbuffer, window

const helpsentences = """
# Exiting

:w    - Write file
:q    - Quit
:wq   - Qrite an quit
:q!   - Force write
:qa!  - Quit all windows
:wqa  - Write and quit all windows
:wqa! - Force quit all window
:w!   - Force write
:wq!  - Force write and quit window

# Changing modes

v       - Visual mode
Ctrl, v - Visual block mode
r       - Replace mode
i       - Insert mode
o       - Insert a new line and start insert mode
a       - Append after the cursor and start insert mode
I       - Same as 0, a
A       -Same as $, a

# Normal mode

h          - Go left
j          - Go down
k          - Go up
l          - Go right
w          - Go forwards to the start of a word
e          - Go forwards to the end of a word
b          - Go backwards to the start of a word
r          - Replace a character at the cursor
Page Up    - Page Up
Page Down  - Page Down
gg         - Go to the first line
g_         - Go to the last non-blank character of the line
G          - Go to the last line
0          - Go to the first line
$          - Go to the end of the line
^          - Go to the non-blank character start of line
{          - Go previous blank line
}          - Go next blank line
Ctrl, w    - Half Page Down
Ctrl - d   - Half Page Up
d, $ or D  - Delete until the end of the line
yy         - Copy a line
y{         - Yank to the previous blank line
y}         - Yank to the next blank line
yl         - Yank a character
p          - Paste the clipboard
n          - Search forwards
:          - Start Ex mode
u          - Undo
Ctrl, r    - Redo
>          - Indent
<          - Unindent
==         - Auto indent
dd         - Delete a line
x          - Delete current character
S or cc    - Delete the characters in current line and start insert mode
s or cl    - Delete current character and enter insert mode
ci"        - Delete inside of double quotes and enter insert mode
ci'        - Delete inside of single quotes and enter insert mode
ciw        - Delete current word and enter insert mode
ci( or ci) - Delete inside of round brackets and enter insert mode
ci[ or ci] - Delete inside of square brackets and enter insert mode
ci{ or ci} - Delete inside of curly brackets and enter insert mode
di"        - Delete inside of double quotes
di'        - Delete inside of single quotes
diw        - Delete current word
di( or di) - Delete inside of round brackets
di[ or di] - Delete inside of square brackets
di{ or di} - Delete inside of curly brackets
*          - Search forwards for the word under cursor
#          - Search backwards for the word under cursor
f          - Jump to next occurrence
F          - Jump to previous occurence
Ctrl, k    - Move next window
Ctrl, j    - Move prev window
zt         - Scroll the screen so the cursor is at the top
zb         - Scroll the screen so the cursor is at the bottom
z.         - Center the screen on the cursor
ZZ         - Write current file and exit
ZQ         - Same as :q!
Ctrl, wc   - CLose current window
/          - Search forwards
?          - Search backwards
\r         - QuickRun

# Visual mode

d or x  - Delete text
y       - Copy text
r       - Replace character
J       - Join lines
u       - Convert to Lowercase
U       - Convert to Uppercase
>       - Indent
<       - Unindent
~       - Toggle case of character under cursor
Ctrl, a - Increase number under cursor
Ctrl, x - Decrease number under cursor
I       - Insert character, multiple lines
Esc     - Go to Normal mode

# Replace mode

Esc       - Go to Normal mode
Backdpace - Undo

# Insert mode

Ctrl, r              - Insert the character which is below the cursor
Ctrl, y              - Insert the character which is above the cursor
Ctrl, i              - Insert a Tab
Ctrl, h or Backdpace - Delete the character before the cursor
Ctrl, t              - Add indent in current line
Ctrl, d              - Remove indent in current line
Ctrl, w              - Delete the word before the cursor
Ctrl, u              - Delete characters before the cursor in current line
Esc                  - Go to Normal mode

# History mode

j     - Go down
k     - Go up
gg    - Go to the first line
G     - Go to the last line
Enter - Open diff
R     - Restore backup file
D     - Delete backup file
r     - Reload backup files

# Diff mode

j     - Go down
k     - Go up
gg    - Go to the first line
G     - Go to the last line

# Filer mode

j     - Go down
k     - Go up
gg    - Go to the first line
G     - Go to the last line
i     - Detail Information
D     - Delete file
v     - Split window and open file or directory

# Ex mode

number - Jump to line number : Example :10
! shell command - Shell command execution

e filename - Open file
ene - Create new empty buffer
new - Create new empty buffer in split window horizontally
vnew - Create new empty buffer in split window vertically

%s/keyword1/keyword2/ - Replace text (normal mode only)

ls - Display all buffer
bprev - Switch to the previous buffer
bnext - Switch to the next buffer
bfirst - Switch to the first buffer
blast - Switch to the last buffer
bd or bd number - Delete buffer
buf - Open buffer manager

vs - Vertical split window
vs filename - Open in vertical split window
sv - Horizontal split window
sp filename - Open in horizontal split window

cws - Create new work space
ws number - Change current work space : Example ws 2
dws - Delete current work space
lsw - Show workspace list in status line

livereload on or livereload on - Change setting of live reload of configuration file
theme themeName - Change color theme : Example theme dark
tab on or tab off - Change setting to tab line
syntax on or syntax off - Change setting to syntax highlighting
tabstop number - Change setting to tabStop : Exmaple tabstop 2
paren on or paren off - Change setting to auto close paren
indent on or indent off - Chnage sestting to auto indent
linenum on or linenum off - Change setting to dispaly line number
statusLine on or statusLine on - Change setting to display stattus bar
realtimesearch on or realtimesearch off - Change setting to real-time search
deleteparen on or deleteparen off - Change setting to auto delete paren
smoothscroll on or smoothscroll off - Change setting to smooth scroll
scrollspeed number - Set smooth scroll speed : Example scrollspeed 10
highlightcurrentword on or highlightcurrentword off - Change setting to highlight other uses of the current word
clipboard on or clipboard off - Change setting to system clipboard
highlightfullspace on or highlightfullspace off - Change setting to highlight full width space
buildonsave on or buildonsave off - Change setting to build on save
indentationlines on  or indentationlines off - Change setting to indentation lines
showGitInactive on or showGitInactive off - Change status line setting to show/hide git branch name in inactive window
noh - Turn off highlights
icon - Setting show/hidden icons in filer mode
deleteTrailingSpaces - Delete trailing spaces
ignorecase - Change setting to ignorecase
smartcase - Change setting to smartcase
highlightCurrentLine on or highlightCurrentLine off - Change the highlight setting of the current line

log - Open messages log viwer

help - Open help

putConfigFile - Put a sample configuration file in ~/.config/moe

run or Q - Quick run

recent - Open recent file selection mode (Only supported on Linux)

history - Open backup file manager

conf - Open configuration mode

debug - Open debug mode
"""

proc initHelpModeBuffer(status: var Editorstatus) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.bufStatus[currentBufferIndex].path = ru"help"

  var line = ""
  for ch in helpSentences:
    if ch == '\n':
      status.bufStatus[currentBufferIndex].buffer.add(line.toRunes)
      line = ""
    else: line.add(ch)

proc isHelpMode(status: Editorstatus): bool =
  let
    currentMode = status.bufStatus[status.workspace[status.currentWorkSpaceIndex].currentMainWindowNode.bufferIndex].mode
    prevMode = status.bufStatus[status.workspace[status.currentWorkSpaceIndex].currentMainWindowNode.bufferIndex].prevMode
  result = currentMode == Mode.help or (prevMode == Mode.help and currentMode == Mode.ex)

proc helpMode*(status: var Editorstatus) =
  status.initHelpModeBuffer
  status.resize(terminalHeight(), terminalWidth())

  let
    currentBufferIndex = status.bufferIndexInCurrentWindow
    currentWorkSpace = status.currentWorkSpaceIndex

  while status.isHelpMode and currentWorkSpace == status.currentWorkSpaceIndex and
        currentBufferIndex == status.bufferIndexInCurrentWindow:
    let currentBufferIndex = status.bufferIndexInCurrentWindow

    status.update

    var windowNode = status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode

    var key = errorKey
    while key == errorKey:
      status.eventLoopTask
      key = getKey(
        status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode)

    if isResizekey(key):
      status.resize(terminalHeight(), terminalWidth())

    elif isControlK(key):
      status.moveNextWindow
    elif isControlJ(key):
      status.movePrevWindow

    elif key == ord(':'):
      status.changeMode(Mode.ex)

    elif key == ord('k') or isUpKey(key):
      status.bufStatus[currentBufferIndex].keyUp(windowNode)
    elif key == ord('j') or isDownKey(key):
      status.bufStatus[currentBufferIndex].keyDown(windowNode)
    elif key == ord('h') or isLeftKey(key) or isBackspaceKey(key):
      windowNode.keyLeft
    elif key == ord('l') or isRightKey(key):
      status.bufStatus[currentBufferIndex].keyRight(windowNode)
    elif key == ord('0') or isHomeKey(key):
      windowNode.moveToFirstOfLine
    elif key == ord('$') or isEndKey(key):
      status.bufStatus[currentBufferIndex].moveToLastOfLine(windowNode)
    elif key == ord('g'):
      if getKey(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode) == 'g':
        status.moveToFirstLine
    elif key == ord('G'):
      status.moveToLastLine
