#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2026 Shuhei Nogawa                                       #
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

## Help viewer state management
##
## This module provides the data structures and operations for the help viewer mode.

const HelpSentences* = """
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
g;         - Go to the previous change position
g,         - Go to the next change position
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
yt any     - Yank characters to a any character
p          - Paste the clipboard
n          - Search forwards
gn         - Go to next search match and select it visually
gN         - Go to previous search match and select it visually
dgn        - Delete next search match
dgN        - Delete previous search match
]c         - Jump to next git change hunk
[c         - Jump to previous git change hunk
:          - Start command mode
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
ciW        - Delete the current WORD and enter insert mode
ci( or ci) - Delete the inside of round brackets and enter insert mode
ci[ or ci] - Delete the inside of square brackets and enter insert mode
ci{ or ci} - Delete the inside of curly brackets and enter insert mode
ca"        - Delete around double quotes and enter insert mode
ca'        - Delete around single quotes and enter insert mode
caw        - Delete a word (with surrounding whitespace) and enter insert mode
caW        - Delete a WORD (with surrounding whitespace) and enter insert mode
ca( or ca) - Delete around round brackets and enter insert mode
ca[ or ca] - Delete around square brackets and enter insert mode
ca{ or ca} - Delete around curly brackets and enter insert mode
cf any     - Delete characters to the any character and enter insert mode
ct any     - Delete characters until the character and enter insert mode
di"        - Delete the inside of double quotes
di'        - Delete the inside of single quotes
diw        - Delete the current word
diW        - Delete the current WORD
di( or di) - Delete the inside of round brackets
di[ or di] - Delete the inside of square brackets
di{ or di} - Delete the inside of curly brackets
da"        - Delete around double quotes (including quotes)
da'        - Delete around single quotes (including quotes)
daw        - Delete a word (including surrounding whitespace)
daW        - Delete a WORD (including surrounding whitespace)
da( or da) - Delete around round brackets (including brackets)
da[ or da] - Delete around square brackets (including brackets)
da{ or da} - Delete around curly brackets (including brackets)
dt any     - Delete characters until the character
yiw        - Yank the current word
yiW        - Yank the current WORD
yi"        - Yank the inside of double quotes
yi'        - Yank the inside of single quotes
yi( or yi) - Yank the inside of round brackets
yi[ or yi] - Yank the inside of square brackets
yi{ or yi} - Yank the inside of curly brackets
yaw        - Yank a word (including surrounding whitespace)
yaW        - Yank a WORD (including surrounding whitespace)
*          - Search forwards for the word under cursor
#          - Search backwards for the word under cursor
f          - Move to next any character on the current line
F          - Move to previous any character on the current line
t          - Move to the left of the any character on the current line
T          - Move to the right of the back any character on the current line
Ctrl-w k   - Move to the next window
Ctrl-w j   - Move to the previous window
zt         - Scroll the screen so the cursor is at the top
zb         - Scroll the screen so the cursor is at the bottom
z.         - Center the screen on the cursor
ZZ         - Write current file and exit
ZQ         - Same as :q!
Ctrl-w c   - Close current window
Ctrl-w +   - Increase window height
Ctrl-w -   - Decrease window height
Ctrl-w >   - Increase window width
Ctrl-w <   - Decrease window width
Ctrl-w =   - Equalize window sizes
Ctrl-w x   - Swap window with next window
/          - Search forwards
?          - Search backwards
\r         - QuickRun
ga         - Show current character info
.          - Repeat the last normal mode command
q any      - Start recording operations for Macros
q          - Stop recoding operations
@ any      - Exec a macro
@:         - Repeat the last command mode command
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
Ctrl-s     - Selection Range (LSP)
Space o    - Document Symbol (LSP)
gt         - Switch to the next buffer
gT         - Switch to the previous buffer
Ctrl-o     - Jump Back (Jumplist)
Ctrl-i     - Jump Forward (Jumplist)
mm         - Toggle bookmark on current line
mn         - Jump to next bookmark
mp         - Jump to previous bookmark
mc         - Clear all bookmarks in current buffer

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
S       - Surround selection with character
J       - Join lines
u       - Convert to lowercase
U       - Convert to uppercase
>       - Indent
<       - Unindent
~       - Toggle case of character under cursor
Ctrl-a  - Increase number under cursor
Ctrl-x  - Decrease number under cursor
I       - Insert character, multiple lines
zf      - Fold selected lines
Ctrl-s  - Selection Range (LSP)
Esc     - Go to Normal mode

# Replace mode

Esc       - Go to Normal mode
Backspace - Undo

# Insert mode

Ctrl-e              - Insert the character which is below the cursor
Ctrl-y              - Insert the character which is above the cursor
Ctrl-i              - Insert a Tab
Ctrl-h or Backspace - Delete the character before the cursor
Ctrl-t              - Add an indent in current line
Ctrl-d              - Remove an indent in current line
Ctrl-w              - Delete the word before the cursor
Ctrl-u              - Delete all characters before the cursor in the current line
Ctrl-r              - Signature Help (LSP)
Ctrl-o              - Execute one Normal mode command and return to Insert mode
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
k     - Go up
gg    - Go to the first line
G     - Go to the last line
Enter - Jump to the destination
Esc   - Quit References mode

# Call hierarchy viewer mode

j     - Go down
k     - Go up
gg    - Go to the first line
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

# Command mode

number          - Jump to line number; e.g. :10
! shell command - Shell command execution
bg              - Pause the editor and show the recent terminal output
man arguments   - Show the given UNIX manual page, if available; e.g. :man man

e filename - Open file
e          - Reload current file (error if unsaved changes)
e!         - Force reload current file (discard unsaved changes)
e! filename - Open file (discard unsaved changes)
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
vs          - Vertical split window
vs filename - Open in a vertical split window
sp          - Horizontal split window
sp filename - Open in a horizontal split window
only        - Close all other windows
filetree      - Toggle FileTree sidebar
filetree path - Toggle FileTree sidebar with specified root path

theme themeName - Change color theme; for example theme dark
noh            - Turn off search highlights
stripwhitespace - Delete trailing spaces

set number / set nonumber (nu/nonu)                         - Show/hide line numbers
set relativenumber / set norelativenumber (rnu/nornu)       - Show/hide relative line numbers
set cursorline / set nocursorline (cul/nocul)               - Highlight the current line
set cursorcolumn / set nocursorcolumn (cuc/nocuc)           - Highlight the current column
set statusline / set nostatusline (stl/nostl)               - Show/hide status line
set syntax / set nosyntax (syn/nosyn)                       - Enable/disable syntax highlighting
set indentationlines / set noindentationlines (indl/noindl) - Enable/disable indentation guide lines
set autoindent / set noautoindent (ai/noai)                 - Enable/disable auto indent
set autocloseparen / set noautocloseparen (acp/noacp)       - Enable/disable auto close paren
set autodeleteparen / set noautodeleteparen (adp/noadp)     - Enable/disable auto delete paren
set clipboard / set noclipboard (cb/nocb)                   - Enable/disable system clipboard
set smoothscroll / set nosmoothscroll (sms/nosms)           - Enable/disable smooth scroll
set livereload / set nolivereload (lr/nolr)                 - Enable/disable live reload of config
set icon / set noicon (icons/noicons)                       - Show/hide icons in filer mode
set highlightcurrentline / set nohighlightcurrentline (hcl/nohcl) - Highlight the current line
set highlightcurrentword / set nohighlightcurrentword (hcw/nohcw) - Highlight other uses of the current word
set highlightfullspace / set nohighlightfullspace (hfs/nohfs)     - Highlight full width space
set highlightparen / set nohighlightparen (hp/nohp)         - Highlight matching paren
set highlightfindchar / set nohighlightfindchar (hfc/nohfc) - Highlight f/F/t/T matches
set highlightcolorcode / set nohighlightcolorcode (hcc/nohcc) - Highlight inline color codes
set multistatusline / set nomultistatusline (msl/nomsl)     - Enable/disable multiple status line
set ignorecase / set noignorecase (ic/noic)                 - Enable/disable ignorecase
set smartcase / set nosmartcase (scs/noscs)                 - Enable/disable smartcase
set incsearch / set noincsearch (is/nois)                   - Enable/disable incremental search
set hlsearch / set nohlsearch (hls/nohls)                   - Enable/disable search highlighting
set buildonsave / set nobuildonsave (bos/nobos)             - Enable/disable build on save
set showgitinactive / set noshowgitinactive (sgi/nosgi)     - Show/hide git branch in inactive window
set wrap / set nowrap                                       - Enable/disable line wrap
set expandtab / set noexpandtab (et/noet)                   - Enable/disable expand tab to spaces
set scrollbar / set noscrollbar                             - Enable/disable scrollbar
set scrollbarwidth=number        - Change scrollbar width; e.g. set scrollbarwidth=2
set tabstop=number (ts)          - Change tab stop width; e.g. set tabstop=2
set shiftwidth=number (sw)       - Change indent width; e.g. set shiftwidth=2
set softtabstop=number (sts)     - Change soft tab stop width; e.g. set softtabstop=4
set scrollfriction=number (sfr)  - Change smooth scroll friction; e.g. set scrollfriction=80.0
set scrollairdrag=number (sad)   - Change smooth scroll air drag; e.g. set scrollairdrag=2.0
build - Build the current buffer
lspfold - LSP Folding Range
lspformat - LSP Document Formatting

log - Open a log viewer for editor log
lsplog - Open a log viewer for LSP log

lsprestart - Restart the current LSP server
lspcallhierarchyincoming - Show incoming calls (callers) at cursor
lspcallhierarchyoutgoing - Show outgoing calls (callees) at cursor

help - Open this help

putconfigfile - Put a sample configuration file in ~/.config/moe

quickrun - Quick run

recent - Open recent file selection mode (Only supported on Linux)

backup - Open backup file manager

config - Open configuration mode

debug - Open debug mode

jump - Open Jump list viewer

terminal         - Open terminal emulator (default shell)
terminal command - Run command in terminal emulator

changes - Show Change list

bookmarks - Show bookmark list

## Runtime Key Mapping

nmap {lhs} {rhs}  - Map keys in Normal mode
imap {lhs} {rhs}  - Map keys in Insert mode
vmap {lhs} {rhs}  - Map keys in Visual modes
rmap {lhs} {rhs}  - Map keys in Replace mode
cmap {lhs} {rhs}  - Map keys in Command mode
map {lhs} {rhs}   - Map keys in all modes

nmap              - List all Normal mode mappings
imap              - List all Insert mode mappings
vmap              - List all Visual mode mappings
rmap              - List all Replace mode mappings
cmap              - List all Command mode mappings
map               - List all mode mappings

nunmap {lhs}      - Remove key mapping in Normal mode
iunmap {lhs}      - Remove key mapping in Insert mode
vunmap {lhs}      - Remove key mapping in Visual modes
runmap {lhs}      - Remove key mapping in Replace mode
cunmap {lhs}      - Remove key mapping in Command mode
unmap {lhs}       - Remove key mapping in all modes

nmapclear         - Clear all mappings in Normal mode
imapclear         - Clear all mappings in Insert mode
vmapclear         - Clear all mappings in Visual modes
rmapclear         - Clear all mappings in Replace mode
cmapclear         - Clear all mappings in Command mode
mapclear          - Clear all mappings in all modes

noremap, nnoremap, inoremap, vnoremap, cnoremap are aliases (all mappings are non-recursive).

Key notation:
  a, j, 0           - Regular keys
  C-s, M-x, C-M-a   - Modifier keys (C=Ctrl, M=Alt)
  Escape, Enter, Tab - Special keys
  Up, Down, F1-F12   - Arrow and function keys
  Space              - Space key
  j j, g g           - Multi-key sequences (space-separated)
  jj, gg             - Vim-style concatenated keys (equivalent to j j, g g)

{rhs} can be a command name or a key sequence (e.g. Escape).
Use :help to see the list of available command names.

Examples:
  :nmap C-s save-and-quit      - Ctrl-S saves and quits (Normal mode)
  :imap jj Escape              - jj exits Insert mode
  :nmap C-a g g                - Ctrl-A goes to first line (Normal mode)
  :vmap C-c Escape             - Ctrl-C exits Visual mode
  :cmap C-a Home               - Ctrl-A moves to start (Command mode)
  :nmap                        - List all Normal mode mappings
  :map                         - List all mode mappings

# Terminal mode

## Terminal-Input sub-mode (default)

All keystrokes are forwarded to the running shell/command.

Ctrl-\ Ctrl-n - Switch to Terminal-Normal sub-mode

## Terminal-Normal sub-mode

i  - Return to Terminal-Input sub-mode
a  - Return to Terminal-Input sub-mode
:  - Enter command mode
"""

import std/[strutils, options]

import buffer

type HelpViewerState* = ref object
  lines*: seq[string] # Help lines to display
  selectedIndex*: int # Currently selected line index (cursor position)
  topLine*: int # Scroll position (first visible line)
  searchQuery*: string # Current search query
  originalBuffer*: TextBuffer # Saved original buffer (restored on exit)

proc newHelpViewerState*(): HelpViewerState =
  ## Create a new help viewer state
  var lines: seq[string]
  for line in HelpSentences.splitLines:
    lines.add(line)

  HelpViewerState(lines: lines, selectedIndex: 0, topLine: 0, searchQuery: "")

proc lineCount*(state: HelpViewerState): int =
  ## Get the number of lines in the help
  state.lines.len

proc getLine*(state: HelpViewerState, index: int): string =
  ## Get a specific line from the help
  if index >= 0 and index < state.lines.len:
    state.lines[index]
  else:
    ""

proc moveUp*(state: HelpViewerState) =
  ## Move selection up
  if state.selectedIndex > 0:
    state.selectedIndex.dec

proc moveDown*(state: HelpViewerState) =
  ## Move selection down
  if state.selectedIndex < state.lines.high:
    state.selectedIndex.inc

proc moveToFirst*(state: HelpViewerState) =
  ## Move to first line
  state.selectedIndex = 0

proc moveToLast*(state: HelpViewerState) =
  ## Move to last line
  if state.lines.len > 0:
    state.selectedIndex = state.lines.high
  else:
    state.selectedIndex = 0

proc halfPageUp*(state: HelpViewerState, viewportHeight: int) =
  ## Move up by half a page
  let halfPage = viewportHeight div 2
  state.selectedIndex = max(0, state.selectedIndex - halfPage)

proc halfPageDown*(state: HelpViewerState, viewportHeight: int) =
  ## Move down by half a page
  let halfPage = viewportHeight div 2
  if state.lines.len > 0:
    state.selectedIndex = min(state.lines.high, state.selectedIndex + halfPage)

proc ensureSelectedVisible*(state: HelpViewerState, viewportHeight: int) =
  ## Ensure the selected line is visible in the viewport
  # Adjust topLine to keep selected line visible
  if state.selectedIndex < state.topLine:
    state.topLine = state.selectedIndex
  elif state.selectedIndex >= state.topLine + viewportHeight:
    state.topLine = state.selectedIndex - viewportHeight + 1

  # Ensure topLine is not negative
  if state.topLine < 0:
    state.topLine = 0

proc setSearchQuery*(state: HelpViewerState, query: string) =
  ## Set the search query
  state.searchQuery = query

proc clearSearch*(state: HelpViewerState) =
  ## Clear the search query
  state.searchQuery = ""

proc hasSearchQuery*(state: HelpViewerState): bool =
  ## Check if there is an active search query
  state.searchQuery.len > 0

proc isLineMatched*(state: HelpViewerState, index: int): bool =
  ## Check if a line matches the current search query (case-insensitive)
  if not state.hasSearchQuery:
    return false
  if index < 0 or index >= state.lines.len:
    return false
  state.lines[index].toLowerAscii.contains(state.searchQuery.toLowerAscii)

proc searchForward*(state: HelpViewerState): Option[int] =
  ## Search forward from current position.
  ## Returns the line index if found, none otherwise.
  if not state.hasSearchQuery:
    return none(int)

  let query = state.searchQuery.toLowerAscii
  # Search from next line to end
  for i in (state.selectedIndex + 1) ..< state.lines.len:
    if state.lines[i].toLowerAscii.contains(query):
      state.selectedIndex = i
      return some(i)

  # Wrap around: search from beginning to current position
  for i in 0 ..< state.selectedIndex:
    if state.lines[i].toLowerAscii.contains(query):
      state.selectedIndex = i
      return some(i)

  none(int)

proc searchBackward*(state: HelpViewerState): Option[int] =
  ## Search backward from current position.
  ## Returns the line index if found, none otherwise.
  if not state.hasSearchQuery:
    return none(int)

  let query = state.searchQuery.toLowerAscii
  # Search from previous line to beginning
  for i in countdown(state.selectedIndex - 1, 0):
    if state.lines[i].toLowerAscii.contains(query):
      state.selectedIndex = i
      return some(i)

  # Wrap around: search from end to current position
  for i in countdown(state.lines.high, state.selectedIndex + 1):
    if state.lines[i].toLowerAscii.contains(query):
      state.selectedIndex = i
      return some(i)

  none(int)

proc searchFirst*(state: HelpViewerState): Option[int] =
  ## Search from the beginning of the document.
  ## Returns the line index if found, none otherwise.
  if not state.hasSearchQuery:
    return none(int)

  let query = state.searchQuery.toLowerAscii
  for i in 0 ..< state.lines.len:
    if state.lines[i].toLowerAscii.contains(query):
      state.selectedIndex = i
      return some(i)

  none(int)

proc createHelpTextBuffer*(state: HelpViewerState): TextBuffer =
  ## Create a TextBuffer from help lines for rendering via the normal view path
  var content = ""
  for i, line in state.lines:
    if i > 0:
      content.add('\n')
    if line.len > 0:
      content.add(' ' & line)
    else:
      content.add("")
  result = newTextBuffer(content)
  result.readOnly = true
