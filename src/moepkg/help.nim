import std/[terminal]
import editorstatus, bufferstatus, ui, movement, unicodeext, gapbuffer, window

const helpsentences = """
# Exiting

:w    - Write file
:q    - Quit
:wq   - Write and quit
:q!   - Force quit
:qa!  - Quit all windows
:wqa  - Write and quit all windows
:wqa! - Force quit all windows
:w!   - Force write
:wq!  - Force write and quit window

# Changing modes

v      - Visual mode
Ctrl-v - Visual block mode
r      - Replace mode
i      - Insert mode
o      - Insert a new line and start insert mode
a      - Append after the cursor and start insert mode
I      - Same as ^i
A      - Same as $a

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
0          - Go to the first character of the line
$          - Go to the end of the line
^          - Go to the first non-blank character of the line
{          - Go to the previous blank line
}          - Go to the next blank line
Ctrl-w     - Half Page Down
Ctrl-d     - Half Page Up
d$ or D    - Delete until the end of the line
yy or Y    - Copy a line
y{         - Yank to the previous blank line
y}         - Yank to the next blank line
yl         - Yank a character
yt any     - Ynak characters to a any character
p          - Paste the clipboard
n          - Search forwards
:          - Start Ex mode
u          - Undo
Ctrl-r     - Redo
>          - Indent
<          - Unindent
==         - Auto indent
dd         - Delete a line
x          - Delete current character
X or dh    - Delete the character before the cursor
S or cc    - Delete the characters in the current line and start insert mode
s or cl    - Delete the current character and enter insert mode
ci"        - Delete the inside of double quotes and enter insert mode
ci'        - Delete the inside of single quotes and enter insert mode
ciw        - Delete the current word and enter insert mode
ci( or ci) - Delete the inside of round brackets and enter insert mode
ci[ or ci] - Delete the inside of square brackets and enter insert mode
ci{ or ci} - Delete the inside of curly brackets and enter insert mode
cf any     - Delete characters to the any character and enter insert mode
di"        - Delete the inside of double quotes
di'        - Delete the inside of single quotes
diw        - Delete the current word
di( or di) - Delete the inside of round brackets
di[ or di] - Delete the inside of square brackets
di{ or di} - Delete the inside of curly brackets
*          - Search forwards for the word under cursor
#          - Search backwards for the word under cursor
f          - Move to next any character on the current line
F          - Move to previous any character on the current line
t          - Move to the left of the any character on the current line
T          - Move to the right of the back any character on the current line
Ctrl-k     - Move to the next window
Ctrl-j     - Move to the previous window
zt         - Scroll the screen so the cursor is at the top
zb         - Scroll the screen so the cursor is at the bottom
z.         - Center the screen on the cursor
ZZ         - Write current file and exit
ZQ         - Same as :q!
Ctrl-w c   - Close current window
/          - Search forwards
?          - Search backwards
\r         - QuickRun
ga         - Show current character info

# Register

"-any key-yy
"-any key-yl
"-any key-yw
"-any key-y}
"-any key-y{
"-any key-p
"-any key-P
"-any key-dd
"-any key-dw
"-any key-d$
"-any key-d0
"-any key-dG
"-any key-dgg
"-any key-d{
"-any key-d}
"-any key-di-any key
"-any key-dh
"-any key-cl
"-any key-s
"-any key-ci-any key

# Visual mode

d or x  - Delete text
y       - Copy text
r       - Replace character
J       - Join lines
u       - Convert to lowercase
U       - Convert to uppercase
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

Ctrl-r              - Insert the character which is below the cursor
Ctrl-y              - Insert the character which is above the cursor
Ctrl-i              - Insert a Tab
Ctrl-h or Backspace - Delete the character before the cursor
Ctrl-t              - Add an indent in current line
Ctrl-d              - Remove an indent in current line
Ctrl-w              - Delete the word before the cursor
Ctrl-u              - Delete all characters before the cursor in the current line
Esc                 - Go to Normal mode

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

j  - Go down
k  - Go up
gg - Go to the first line
G  - Go to the last line

# Filer mode

j  - Go down
k  - Go up
gg - Go to the first line
G  - Go to the last line
i  - Detail Information
D  - Delete file
v  - Split window and open file or directory

# Ex mode

number          - Jump to line number; for example :10
! shell command - Shell command execution

e filename - Open file
ene        - Create a new empty buffer
new        - Create a new empty buffer in a horizontally split window
vnew       - Create a new empty buffer in a vertically split window

%s/keyword1/keyword2/ - Replace text (normal mode only)

ls              - Display all buffers
bprev           - Switch to the previous buffer
bnext           - Switch to the next buffer
bfirst          - Switch to the first buffer
blast           - Switch to the last buffer
bd or bd number - Delete buffer
buf             - Open the buffer manager

vs          - Vertical split window
vs filename - Open in a vertical split window
sv          - Horizontal split window
sp filename - Open in a horizontal split window

livereload on or livereload on - Change setting of live reload of configuration file
theme themeName - Change color theme; for example theme dark
tab on or tab off - Change setting to tab line
syntax on or syntax off - Change setting to syntax highlighting
tabstop number - Change setting to tabStop; for example tabstop 2
paren on or paren off - Change setting to auto close paren
indent on or indent off - Chnage sestting to auto indent
linenum on or linenum off - Change setting to dispaly line number
statusLine on or statusLine on - Change setting to display stattus bar
realtimesearch on or realtimesearch off - Change setting to real-time search
deleteparen on or deleteparen off - Change setting to auto delete paren
smoothscroll on or smoothscroll off - Change setting to smooth scroll
scrollspeed number - Set smooth scroll speed; for example scrollspeed 10
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
build - Build the current buffer

log - Open messages log viewer

help - Open this help

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
    bufferIndex = status.mainWindow.currentMainWindowNode.bufferIndex
    currentMode = status.bufStatus[bufferIndex].mode
    prevMode = status.bufStatus[bufferIndex].prevMode

  result = currentMode == Mode.help or (prevMode == Mode.help and currentMode == Mode.ex)

proc helpMode*(status: var Editorstatus) =
  status.initHelpModeBuffer
  status.resize(terminalHeight(), terminalWidth())

  let currentBufferIndex = status.bufferIndexInCurrentWindow

  while status.isHelpMode and
        currentBufferIndex == status.bufferIndexInCurrentWindow:

    let currentBufferIndex = status.bufferIndexInCurrentWindow

    status.update

    var key = errorKey
    while key == errorKey:
      status.eventLoopTask
      key = getKey(currentMainWindowNode)

    if isResizekey(key):
      status.resize(terminalHeight(), terminalWidth())

    elif isControlK(key):
      status.moveNextWindow
    elif isControlJ(key):
      status.movePrevWindow

    elif key == ord(':'):
      status.changeMode(Mode.ex)

    elif key == ord('k') or isUpKey(key):
      status.bufStatus[currentBufferIndex].keyUp(currentMainWindowNode)
    elif key == ord('j') or isDownKey(key):
      status.bufStatus[currentBufferIndex].keyDown(currentMainWindowNode)
    elif key == ord('h') or isLeftKey(key) or isBackspaceKey(key):
      currentMainWindowNode.keyLeft
    elif key == ord('l') or isRightKey(key):
      status.bufStatus[currentBufferIndex].keyRight(currentMainWindowNode)
    elif key == ord('0') or isHomeKey(key):
      currentMainWindowNode.moveToFirstOfLine
    elif key == ord('$') or isEndKey(key):
      status.bufStatus[currentBufferIndex].moveToLastOfLine(
        currentMainWindowNode)
    elif key == ord('g'):
      if getKey(currentMainWindowNode) == 'g':
        status.moveToFirstLine
    elif key == ord('G'):
      status.moveToLastLine
