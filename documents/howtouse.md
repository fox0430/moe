# How to use

# Table of Contents

|                               |                             |                               |                             |
|:-----------------------------:|:---------------------------:|:-----------------------------:|:---------------------------:|
| [Normal Mode](#normal-mode)   | [Visual Mode](#visual-mode) | [Replace Mode](#replace-mode) | [Insert Mode](#insert-mode) |
| [History Mode](#history-mode) | [Diff Mode](#diff-mode)     | [Filer Mode](#filer-mode)     | [Ex Mode](#insert-mode)     |
| [Exiting](#exiting)           | [Changing Modes](#changing-modes) | [Go To Bottom](#x) |                             |

## Exiting

- Check the command bar...

```:w``` - Write file  
```:q``` - Quit  
```:wq``` - Write file and quit  
```:q!``` - Force quit  
```:qa``` - Quit all window  
```:wqa``` - Write and quit all window  
```:qa!``` - Force quit all window  


## Changing Modes

- In **Normal Mode**...

|                               |                             |                               |                             |
|:-----------------------------:|:---------------------------:|:-----------------------------:|:---------------------------:|
| <kbd>**v**</kbd> Visual mode  | <kbd>**Ctrl**</kbd> <kbd>**v**</kbd> Visual Block mode | <kbd>**r**</kbd> Replace mode | <kbd>**i**</kbd> Insert mode |
| <kbd>**o**</kbd> Insert a new line and start insert mode | <kbd>**a**</kbd> Append after the cursor and start insert mode | <kbd>**r**</kbd> Replace a character at the cursor | <kbd>**A**</kbd> Same as <kbd>**$**</kbd> <kbd>**a**</kbd> |
| <kbd>**I**</kbd> Same as <kbd>**0**</kbd> <kbd>**a**</kbd> | |                              |                             |


## Normal mode

|                               |                             |                               |                             |
|:-----------------------------:|:---------------------------:|:-----------------------------:|:---------------------------:|
| <kbd>**h**</kbd> Go Left :arrow_left: | <kbd>**j**</kbd> Go Down :arrow_down: | <kbd>**k**</kbd> Go Up :arrow_up: | <kbd>**l**</kbd> Go Rigth :arrow_right: |
| <kbd>**w**</kbd> Go forwards to the start of a word :arrow_right: | <kbd>**e**</kbd> Go forwards to the end of a word :arrow_right: | <kbd>**b**</kbd> Go backwards to the start of a word :arrow_left: |  |
| <kbd>**Page Up**</kbd> Page Up :arrow_up: | <kbd>**Page Down**</kbd> Page Down :arrow_down: | <kbd>**g**</kbd> <kbd>**g**</kbd> Go to the first line :arrow_up: | <kbd>**g**</kbd> <kbd>**_**</kbd> Go to the last non-blank character of the line :arrow_right: |
| <kbd>**G**</kbd> Go to the last line :arrow_down: | <kbd>**0**</kbd> Go to the first line :arrow_up: | <kbd>**$**</kbd> Go to the end of the line :arrow_right: | <kbd>**^**</kbd> Go to the non-blank character start of line :arrow_left: |
| <kbd>**Ctrl**</kbd> <kbd>**u**</kbd> Half Page Down :arrow_down: | <kbd>**Ctrl**</kbd> <kbd>**d**</kbd> Half Page Up :arrow_up: |  |  |
| <kbd>**u**</kbd> Undo | <kbd>**Ctrl**</kbd> <kbd>**r**</kbd> Redo | <kbd>**>**</kbd> Indent | <kbd>**<**</kbd> Unindent |
| <kbd>**=**</kbd> <kbd>**=**</kbd> Auto Indent | <kbd>**d**</kbd> <kbd>**d**</kbd> Delete a line | <kbd>**x**</kbd> Delete current character | <kbd>**S**</kbd> OR <kbd>**c**</kbd> <kbd>**c**</kbd> Delete the characters in current line and start insert mode |
| <kbd>**d**</kbd> <kbd>**$**</kbd> OR  <kbd>**D**</kbd> Delete until the end of the line |  |  |  |
| <kbd>**y**</kbd> <kbd>**y**</kbd> Copy a line | <kbd>**p**</kbd> Paste the clipboard | <kbd>**n**</kbd> Search forwards | <kbd>**N**</kbd> Search backwards |
| <kbd>*</kbd> Search forwards for the word under cursor | <kbd>**#**</kbd> Search backwards for the word under cursor | <kbd>**f**</kbd> Jump to next occurrence | <kbd>**F**</kbd> Jump to previous occurence |
| <kbd>**Ctrl**</kbd> <kbd>**k**</kbd> Move next window | <kbd>**Ctrl**</kbd> <kbd>**j**</kbd> Move prev window  | <kbd>**z**</kbd> <kbd>**t**</kbd> Scroll the screen so the cursor is at the top | <kbd>**z**</kbd> <kbd>**b**</kbd> Scroll the screen so the cursor is at the bottom |
| <kbd>**z**</kbd> <kbd>**.**</kbd> Center the screen on the cursor | <kbd>**Z**</kbd> <kbd>**Z**</kbd> Write current file and exit | <kbd>**Z**</kbd> <kbd>**Q**</kbd> Same as `:q!` | <kbd>**Ctrl**</kbd> <kbd>**w**</kbd> <kbd>**c**</kbd> Close current window |
| <kbd>**/**</kbd> Search text | <kbd>**:**</kbd> Start Ex mode | <kbd>**\**</kbd> <kbd>**r**</kbd> Quick Run | <kbd>**/**</kbd> `keyword` Search forwards |
| <kbd>**?**</kbd> `keyword` Search backwards  |  |  |  |


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


## Hitory mode (Backup file manager)  

```j``` - ↓  
```k``` - ↑  
```Enter``` - Open diff viewer  
```R``` - Restore from backup file  
```D``` - Delete backup file  
```r``` - Reload backup files  
```gg``` - Move to the first line  
```G``` - Move to the last line  


## Diff mode (Diff viewer)    

```j``` - ↓  
```k``` - ↑  
```gg``` - Move to the first line  
```G``` - Move to the last line  


## Filer mode

```D``` - Delete file  
```g``` - Go to top of list  
```G``` - Go to last of list  
```i``` - Detail information  
```v``` - Split window and open file or directory  


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
```ignorecase``` - Change setting to ignorecase  
```smartcase``` - Change setting to smartcase  

```log``` - Open messages log viwer  

```help``` - Open help

```putConfigFile``` - Put a sample configuration file in ~/.config/moe

```run``` or ```Q``` - Quick run

```recent``` - Open recent file selection mode (Only supported on Linux)  

```history``` - Open backup file manager  

```conf``` - Open configuration mode


[Go To Top](#table-of-contents)
#### x
