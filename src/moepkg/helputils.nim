#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2023 Shuhei Nogawa                                       #
#                                                                              #
#  This program is free software: you can redistribute it and/or modify        #
#  it under the terms of the GNU General Public License as published by        #
#  the Free Software Foundation, either version 3 of the License, or           #
#  (at your option) any later version.                                         #
#                                                                              #
#  This program is distributed in the hope that it will be useful,             #
#  but WITHOUT ANY WARRANTY; without even the implied warranty of              #
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the               #
#  GNU General Public License for more details.                                #
#                                                                              #
#  You should have received a copy of the GNU General Public License           #
#  along with this program.  If not, see <https://www.gnu.org/licenses/>.      #
#                                                                              #
#[############################################################################]#

import std/strutils
import unicodeext

const HelpSentences = """
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
V      - Visual line mode
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
H          - Move to the top line of the screen
M          - Move to the center line of the screen
L          - Move to the bottom line of the screen
Ctrl-w     - Half Page Down
Ctrl-d     - Half Page Up
%          - Move to matching pair of paren
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
ct any     - Delete characters until the character and enter insert mode
di"        - Delete the inside of double quotes
di'        - Delete the inside of single quotes
diw        - Delete the current word
di( or di) - Delete the inside of round brackets
di[ or di] - Delete the inside of square brackets
di{ or di} - Delete the inside of curly brackets
dt any     - Delete characters until the character
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
.          - Repeat the last normal mode command
q any      - Start recording operations for Macros
q          - Stop recoding operations
@ any      - Exec a macro
K          - Hover (LSP)
gc         - Goto Declaration (LSP)
gd         - Goto Definition (LSP)
gy         - Goto Type Definition (LSP)
gi         - Goto Implementation (LSP)
gr         - References (LSP)
gh         - Open Call hierarchy viewer (LSP)
gl         - Document Link (LSP)
Space r    - Rename (LSP)
\ r        - Code Lens (LSP)
zd         - Delete folding lines
zD         - Delete all folding lines

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
zf      - Fold selected lines
Esc     - Go to Normal mode

# Replace mode

Esc       - Go to Normal mode
Backspace - Undo

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

# Backup mode

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

# References mode

j     - Go down
k     - Go down
g     - Go to the first line
G     - Go to the last line
Enter - Jump to the destination
ESC   - Quit References mode

# Call hierarchy viewer mode

j     - Go down
k     - Go down
g     - Go to the first line
G     - Go to the last line
Enter - Jump to the destination
i     - Incoming call
o     - Outgoing call

# Filer mode

j  - Go down
k  - Go up
gg - Go to the first line
G  - Go to the last line
i  - Detail Information
D  - Delete file
v  - Split window and open file or directory

# Ex mode

number          - Jump to line number; e.g. :10
! shell command - Shell command execution
bg              - Pause the editor and show the recent terminal output
man arguments   - Show the given UNIX manual page, if available; e.g. :man man

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
indent on or indent off - Change setting to auto indent
linenum on or linenum off - Change setting to display line number
statusLine on or statusLine on - Change setting to display status bar
realtimesearch on or realtimesearch off - Change setting to real-time search
deleteparen on or deleteparen off - Change setting to auto delete paren
smoothscroll on or smoothscroll off - Change setting to smooth scroll
scrollMinDelay number - Set smooth scroll min delay; for example scrollMinDelay 10
scrollMaxDelay number - Set smooth scroll max delay; for example scrollMaxDelay 10
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
lspFold - LSP Folding Range

log - Open a log viewer for editor log
lspLog- Open a log viewer for LSP log

help - Open this help

putConfigFile - Put a sample configuration file in ~/.config/moe

run - Quick run

recent - Open recent file selection mode (Only supported on Linux)

backup - Open backup file manager

conf - Open configuration mode

debug - Open debug mode
"""

proc initHelpModeBuffer*(): seq[Runes] =
  for line in HelpSentences.splitLines:
    result.add line.toRunes
