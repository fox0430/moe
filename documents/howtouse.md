# How to use


## Exiting

Check command bar  

```:w``` - Write file  
```:q``` - Quit  
```:wq``` - Write file and quit  
```:q!``` - Force quit  
```:qa``` - Quit all window  
```:wqa``` - Write and quit all window  
```:qa!``` - Force quit all window  


## Normal mode

```h``` - ←  
```j``` or ```+``` - ↓  
```k``` or ```-``` - ↑  
```l``` - →  
```w``` - Move forwards to the start of a word  
```e``` - Move forwards to the end of a word  
```b``` - Move backwards to the start of a word  
```Page Up``` - Page up  
```Page Down``` - Page down  
```gg``` - Move to the first line  
```g_``` - Move to the last non-blank character of the line  
```G``` - Move to the last line  
```0``` - (zero) First of the line  
```$``` - End of the line  
```^``` or ```_``` -  Move to beginning of non-blank characters in a line  

```Ctrl-u``` - Half page down  
```Ctrl-d``` - Half page up  

```u``` - Undo  
```Ctrl-r``` - Redo  

```v``` - Start visual mode  
```Ctrl-v``` - Start visual block mode  
```r``` - Start replace mode  
```i``` - Start insert mode  
```o``` - Insert a new line and start insert mode  
```a``` - Append after the cursor and start insert mode  
```r``` - Replace a character at the cursor  
```A``` - Same as $a  
```I``` - Same as 0a  

```>``` - Indent  
```<``` - Unindent  
```==``` Auto indent

```dd``` - Delete(cut) a line  
```d$``` or ```D``` -  Delete the characters under the cursor until the end of the line  

```x``` - Delete(cut) current character  

```S``` or ```cc``` - Delete the characters in current line and start insert mode  

```yy``` - Copy a line  
```p``` - Paste the clipboard  

```n``` - Repeat search in same direction  
```N``` - Repeat search in opposite direction  

```*``` - Search forward for the word in under the cursor  
```#``` - Search backward for the word in under the cursor  

```f``` - Jump to next occurrence  
```F``` - Jump to previous occurence  

```Ctrl-k``` - Move next window  
```Ctrl-j``` - Move prev window  

```z.``` - Center the screen on the cursor  
```zt``` - Scroll the screen so the cursor is at the top  
```zb``` - Scroll the screen so the cursor is at the bottom  

```ZZ``` - Write current file and exit  
```ZQ``` - Same as ":q!"  

```/``` - Search text  
```:``` - Start ex mode  

```Ctrl-w c``` - Close current window  

```/keyword``` - Search forward  
```?keyword``` - Search backward  

```\-r``` - Quick run  

## Visual (block) mode

```d ```or ```x``` - Delete(cut) text  
```y``` - Copy text  
```r``` - Replace character  
```J``` - Join lines  
```u``` - Convert string to lowercase  
```U``` - Convert string to uppercase  

```>``` - Indent  
```<``` - Unindent  

```Ctrl-a``` - Increas number under the cursor  
```Ctrl-x``` - Decreas number under the cursor  

```~``` - Toggle case of the character under the cursor  

```I``` - Insert character multiple lines  


```Esc``` - Start normal mode  


## Replace mode

```Esc``` - Start normal mode  
```Backspace``` - undo

## Insert mode

```Ctrl-e``` Insert the character which is below the cursor  
```Ctrl-y``` Insert the character which is above the cursor  
```Ctrl-i``` Insert a tab  

```Ctrl-t``` Add indent in current line  
```Ctrl-d``` Delete indent in current line  

```Backspace``` or ```Ctrl-h``` Delete the character before the cursor  

```Ctrl-w``` Delete the word before the cursor  
```Ctrl-u``` Delete characters before the cursor in current line  

```Esc``` or ```Ctrl-[``` - Start normal mode  


## Filer mode

```D``` - Delete file  
```g``` - Go to top of list  
```G``` - Go to last of list  
```i``` - Detail information  


## Ex mode

```number``` - Jump to line number : Exmaple ```:10```  
```!``` shell command - Shell command execution  

```e``` filename - Open file  
```ene``` - Create new empty buffer  
```new``` - Create new empty buffer in split window horizontally  
```vnew``` - Create new empty buffer in split window vertically  

```%s/keyword1/keyword2/``` - Replace text (normal mode only)  

```ls``` - Display all buffer  
```bprev``` - Switch to the previous buffer  
```bnext``` - Switch to the next buffer  
```bfirst``` - Switch to the first buffer  
```blast``` - Switch to the last buffer  
```bd``` or ```bd number``` - Delete buffer  
```buf``` - Open buffer manager  

```vs``` - Vertical split window  
```vs filename``` - Open in vertical split window  
```sv``` - Horizontal split window  
```sp filename``` - Open in horizontal split window  

```cws``` - Create new work space  
```ws number``` - Change current work space : Example ```ws 2```  
```dws``` - Delete current work space  
```lsw``` - Show workspace list in status bar  

```livereload on``` or ```livereload on``` - Change setting of live reload of configuration file  
```theme themeName``` - Change color theme : Example ```theme dark```  
```tab on``` or ```tab off``` - Change setting to tab line  
```syntax on``` or ```syntax off``` - Change setting to syntax highlighting  
```tabstop number``` - Change setting to tabStop : Exmaple ```tabstop 2```  
```paren on``` or ```paren off``` - Change setting to auto close paren  
```indent on``` or ```indent off``` - Chnage sestting to auto indent  
```linenum on``` or ```linenum off``` - Change setting to dispaly line number  
```statusbar on``` or ```statusbar on``` - Change setting to display stattus bar  
```realtimesearch on``` or ```realtimesearch off``` - Change setting to real-time search   
```deleteparen on``` or ```deleteparen off``` - Change setting to auto delete paren  
```smoothscroll on``` or ```smoothscroll off``` - Change setting to smooth scroll  
```scrollspeed number``` - Set smooth scroll speed : Example ```scrollspeed 10```  
```highlightcurrentword on``` or ```highlightcurrentword off``` - Change setting to highlight other uses of the current word  
```clipboard on``` or ```clipboard off``` - Change setting to system clipboard  
```highlightfullspace on``` or ```highlightfullspace off``` - Change setting to highlight full width space  
```buildonsave on``` or ```buildonsave off``` - Change setting to build on save  
```indentationlines on ``` or ```indentationlines off``` - Change setting to indentation lines  
```showGitInactive on``` or ```showGitInactive off``` - Change status bar setting to show/hide git branch name in inactive window  
```noh``` - Turn off highlights  
```icon``` - Setting show/hidden icons in filer mode  
```deleteTrailingSpaces``` - Delete trailing spaces  

```log``` - Open messages log viwer  

```help``` - Open help

```putConfigFile``` - Put a sample configuration file in ~/.config/moe

```run``` or ```Q``` - Quick run

```recent``` - Open recent file selection mode (Only supported on Linux)  
