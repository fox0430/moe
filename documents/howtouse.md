# How to use

# Table of Contents

|                               |                             |                               |                             |                                   |
|:-----------------------------:|:---------------------------:|:-----------------------------:|:---------------------------:|:---------------------------------:|
| [Normal Mode](#normal-mode)   | [Register](#register) | [Visual Mode](#visual-block-mode) | [Replace Mode](#replace-mode) | [Insert Mode](#insert-mode) | 
| [History Mode](#history-mode)     | [Ex Mode](#ex-mode)       | [Diff Mode](#diff-mode)     | [Filer Mode](#filer-mode)     | [Exiting](#exiting)         |
| [Changing Modes](#changing-modes) |


## Exiting

<details open >
  <summary>Check the command bar</summary>

|                               |                             |                               |
|:-----------------------------:|:---------------------------:|:-----------------------------:|
| <kbd>**:**</kbd> <kbd>**w**</kbd> Write file | <kbd>**:**</kbd> <kbd>**q**</kbd> Quit | <kbd>**:**</kbd> <kbd>**w**</kbd> <kbd>**q**</kbd> Write and Quit |
| <kbd>**:**</kbd> <kbd>**q**</kbd> <kbd>**!**</kbd> Force Quit | <kbd>**:**</kbd> <kbd>**q**</kbd> <kbd>**a**</kbd> Quit All Windows | <kbd>**:**</kbd> <kbd>**w**</kbd> <kbd>**q**</kbd> <kbd>**a**</kbd> Write and Quit All Window |
| <kbd>**:**</kbd> <kbd>**q**</kbd> <kbd>**a**</kbd> <kbd>**!**</kbd> Force Quit All Window | <kbd>**:**</kbd> <kbd>**w**</kbd> <kbd>**!**</kbd> Force write | <kbd>**:**</kbd> <kbd>**w**</kbd> <kbd>**q**</kbd> <kbd>**!**</kbd> Force write and quit window |

</details>


## Changing Modes

<details open>
  <summary>In Normal Mode</summary>

|                               |                             |                               |                             |
|:-----------------------------:|:---------------------------:|:-----------------------------:|:---------------------------:|
| <kbd>**v**</kbd><br>Visual mode  | <kbd>**Ctrl**</kbd> <kbd>**v**</kbd><br>Visual Block mode | <kbd>**r**</kbd><br>Replace mode | <kbd>**i**</kbd><br>Insert mode |
| <kbd>**o**</kbd><br>Insert a new line and start insert mode | <kbd>**a**</kbd><br>Append after the cursor and start insert mode | <kbd>**I**</kbd><br>Same as <kbd>**0**</kbd> <kbd>**a**</kbd> | <kbd>**A**</kbd><br>Same as <kbd>**$**</kbd> <kbd>**a**</kbd> |

</details>


## Normal mode

<details open>
  <summary>The Default Mode</summary>

|                               |                             |                               |                             |
|:-----------------------------:|:---------------------------:|:-----------------------------:|:---------------------------:|
| <kbd>**h**</kbd><br>Go Left :arrow_left: | <kbd>**j**</kbd><br> Go Down :arrow_down: | <kbd>**k**</kbd><br> Go Up :arrow_up: | <kbd>**l**</kbd><br> Go Rigth :arrow_right: |
| <kbd>**w**</kbd><br>Go forwards to the start of a word :arrow_right: | <kbd>**e**</kbd><br> Go forwards to the end of a word :arrow_right: | <kbd>**b**</kbd><br> Go backwards to the start of a word :arrow_left: | <kbd>**{**</kbd><br> Go previous blank line |
| <kbd>**}**</kbd><br> Go next blank line | <kbd>**r**</kbd><br> Replace a character at the cursor | <kbd>**Page Up**</kbd><br>Page Up :arrow_up: | <kbd>**Page Down**</kbd><br> Page Down :arrow_down: |
| <kbd>**g**</kbd> <kbd>**g**</kbd><br> Go to the first line :arrow_up: | <kbd>**g**</kbd> <kbd>**_**</kbd><br> Go to the last non-blank character of the line :arrow_right: | <kbd>**G**</kbd><br>Go to the last line :arrow_down: | <kbd>**0**</kbd><br> Go to the first line :arrow_up: |
| <kbd>**$**</kbd><br> Go to the end of the line :arrow_right: | <kbd>**^**</kbd><br> Go to the non-blank character start of line :arrow_left: | <kbd>**Ctrl**</kbd> <kbd>**u**</kbd><br>Half Page Down :arrow_down: | <kbd>**Ctrl**</kbd> <kbd>**d**</kbd><br> Half Page Up :arrow_up: |
| <kbd>**d**</kbd> <kbd>**$**</kbd> OR  <kbd>**D**</kbd><br> Delete until the end of the line | <kbd>**:**</kbd><br> Start Ex mode | <kbd>**u**</kbd><br>Undo | <kbd>**Ctrl**</kbd> <kbd>**r**</kbd><br> Redo |
| <kbd>**>**</kbd><br> Indent | <kbd>**<**</kbd><br> Unindent | <kbd>**=**</kbd> <kbd>**=**</kbd><br>Auto Indent | <kbd>**d**</kbd> <kbd>**d**</kbd><br> Delete a line |
| <kbd>**d**</kbd> <kbd>**w**</kbd><br> Delete a word | <kbd>**c**</kbd> <kbd>**i**</kbd> <kbd>**"**</kbd><br> Delete inside double quotes and enter insert mode | <kbd>**c**</kbd> <kbd>**i**</kbd> <kbd>**'**</kbd><br> Delete inside sinble quotes and enter insert mode | <kbd>**c**</kbd> <kbd>**i**</kbd> <kbd>**(**</kbd><br> OR <kbd>**c**</kbd> <kbd>**i**</kbd> <kbd>**)**</kbd><br> Delete inside round brackets and enter insert mode |
| <kbd>**c**</kbd> <kbd>**i**</kbd> <kbd>**[**</kbd><br> OR <kbd>**c**</kbd> <kbd>**i**</kbd> <kbd>**]**</kbd><br> Delete inside square brackets and enter insert mode | <kbd>**c**</kbd> <kbd>**i**</kbd> <kbd>**{**</kbd><br> OR <kbd>**c**</kbd> <kbd>**i**</kbd> <kbd>**}**</kbd><br> Delete inside curly brackets and enter insert mode | <kbd>**c**</kbd> <kbd>**i**</kbd> <kbd>**w**</kbd><br> Delete word and enter insert mode |  <kbd>**d**</kbd> <kbd>**i**</kbd> <kbd>**"**</kbd><br> Delete inside double quotes |
| <kbd>**d**</kbd> <kbd>**i**</kbd> <kbd>**'**</kbd><br> Delete inside sinble quotes | <kbd>**d**</kbd> <kbd>**i**</kbd> <kbd>**(**</kbd><br> OR <kbd>**d**</kbd> <kbd>**i**</kbd> <kbd>**)**</kbd><br> Delete inside round brackets | <kbd>**d**</kbd> <kbd>**i**</kbd> <kbd>**[**</kbd><br> OR <kbd>**d**</kbd> <kbd>**i**</kbd> <kbd>**]**</kbd><br> Delete inside square brackets | <kbd>**d**</kbd> <kbd>**i**</kbd> <kbd>**{**</kbd><br> OR <kbd>**d**</kbd> <kbd>**i**</kbd> <kbd>**}**</kbd><br> Delete inside curly brackets | 
| <kbd>**d**</kbd> <kbd>**i**</kbd> <kbd>**w**</kbd><br> Delete word | <kbd>**x**</kbd><br> Delete current character | <kbd>**S**</kbd> OR <kbd>**c**</kbd> <kbd>**c**</kbd><br> Delete the characters in current line and start insert mode | <kbd>**y**</kbd> <kbd>**y**</kbd> OR <kbd>**Y**</kbd><br>Copy a line |
| <kbd>**p**</kbd><br> Paste the clipboard | <kbd>**n**</kbd><br> Search forwards | <kbd>**N**</kbd><br> Search backwards | <kbd> * </kbd><br>Search forwards for the word under cursor |
| <kbd>**#**</kbd><br>Search backwards for the word under cursor | <kbd>**f**</kbd><br>Jump to next occurrence | <kbd>**F**</kbd><br>Jump to previous occurence | <kbd>**Ctrl**</kbd> <kbd>**k**</kbd><br>Move next window |
| <kbd>**Ctrl**</kbd> <kbd>**j**</kbd><br>Move prev window  | <kbd>**z**</kbd> <kbd>**t**</kbd><br>Scroll the screen so the cursor is at the top | <kbd>**z**</kbd> <kbd>**b**</kbd><br>Scroll the screen so the cursor is at the bottom | <kbd>**z**</kbd> <kbd>**.**</kbd><br>Center the screen on the cursor |
| <kbd>**Z**</kbd> <kbd>**Z**</kbd><br>Write current file and exit | <kbd>**Z**</kbd> <kbd>**Q**</kbd><br>Same as `:q!` | <kbd>**Ctrl**</kbd> <kbd>**w**</kbd> <kbd>**c**</kbd><br>Close current window | <kbd>**?**</kbd><br>`keyword` Search backwards |
| <kbd>**/**</kbd><br>`keyword` Search forwards | <kbd>**\\**</kbd> <kbd>**r**</kbd><br>Quick Run | <kbd>**s**</kbd> OR <kbd>**c**</kbd><kbd>**u**</kbd><br> Delete current charater and enter insert mode | <kbd>**y**</kbd><kbd>**{**</kbd><br> Yank to the previous blank line |
| <kbd>**y**</kbd><kbd>**}**</kbd><br> Yank to the next blank line | <kbd>**y**</kbd><kbd>**l**</kbd><br> Yank a character| <kbd>**X**</kbd> OR <kbd>**d**</kbd><kbd>**h**</kbd><br> Cut a character before cursor | <kbd>**g**</kbd><kbd>**a**</kbd><br> Show current character info |
| <kbd>**t**</kbd><kbd>**x**</kbd><br> Move to the left of the next ```x``` (any character) on the current line | <kbd>**T**</kbd><kbd>**x**</kbd><br> Move to the right of the back ```x ``` (any character) on the current line | <kbd>**y**</kbd><kbd>**t**</kbd><br><kbd>**Any key**</kbd><br> Yank characters to an any character | <kbd>**c**</kbd><kbd>**f**</kbd><br><kbd>**Any key**</kbd><br> Delete characters to an any character and enter insert mode |

</details>

## Register

<details open>
  <summary>Register operations</summary>

  |                               |                             |                               |                             |
  |:-----------------------------:|:---------------------------:|:-----------------------------:|:---------------------------:|
  | <kbd>**"**</kbd> <kbd>**register name**</kbd> <kbd>**y**</kbd> <kbd>**y**</kbd> | <kbd>**"**</kbd> <kbd>**register name**</kbd> <kbd>**y**</kbd> <kbd>**l**</kbd> | <kbd>**"**</kbd> <kbd>**register name**</kbd> <kbd>**y**</kbd> <kbd>**w**</kbd> | <kbd>**"**</kbd> <kbd>**register name**</kbd> <kbd>**y**</kbd> <kbd>**{**</kbd> |
  | <kbd>**"**</kbd> <kbd>**register name**</kbd> <kbd>**y**</kbd> <kbd>**}**</kbd> | <kbd>**"**</kbd> <kbd>**register name**</kbd> <kbd>**p**</kbd> | <kbd>**"**</kbd> <kbd>**register name**</kbd> <kbd>**P**</kbd> | <kbd>**"**</kbd> <kbd>**register name**</kbd> <kbd>**d**</kbd> <kbd>**d**</kbd> |
  | <kbd>**"**</kbd> <kbd>**"**</kbd> <kbd>**register name**</kbd> <kbd>**d**</kbd> <kbd>**w**</kbd> | <kbd>**"**</kbd> <kbd>**register name**</kbd> <kbd>**d**</kbd> <kbd>**$**</kbd> | <kbd>**"**</kbd> <kbd>**register name**</kbd> <kbd>**d**</kbd> <kbd>**0**</kbd> | <kbd>**"**</kbd> <kbd>**register name**</kbd> <kbd>**d**</kbd> <kbd>**G**</kbd> |
  | <kbd>**"**</kbd> <kbd>**register name**</kbd> <kbd>**d**</kbd> <kbd>**g**</kbd> <kbd>**g**</kbd> | <kbd>**"**</kbd> <kbd>**register name**</kbd> <kbd>**d**</kbd> <kbd>**{**</kbd> | <kbd>**"**</kbd> <kbd>**register name**</kbd> <kbd>**d**</kbd> <kbd>**}**</kbd> | <kbd>**"**</kbd> <kbd>**register name**</kbd> <kbd>**d**</kbd> <kbd>**i**</kbd> <kbd>**any key**</kbd> |
  | <kbd>**"**</kbd> <kbd>**register name**</kbd> <kbd>**d**</kbd> <kbd>**h**</kbd> | <kbd>**"**</kbd> <kbd>**register name**</kbd> <kbd>**c**</kbd> <kbd>**l**</kbd> OR <kbd>**"**</kbd> <kbd>**register name**</kbd> <kbd>**s**</kbd> | <kbd>**"**</kbd> <kbd>**register name**</kbd> <kbd>**c**</kbd> <kbd>**i**</kbd> <kbd>**any key**</kbd> |
 
</details>

## Visual block mode

<details open>
  <summary>Visual Selection</summary>

|                               |                             |                               |                             |                                   |
|:-----------------------------:|:---------------------------:|:-----------------------------:|:---------------------------:|:---------------------------------:|
| <kbd>**d**</kbd> OR <kbd>**x**</kbd><br> Delete text | <kbd>**y**</kbd><br> Copy text | <kbd>**r**</kbd><br> Replace character | <kbd>**J**</kbd><br> Join lines | <kbd>**J**</kbd><br> Join lines |
| <kbd>**u**</kbd><br> Convert to Lowercase | <kbd>**U**</kbd><br> Convert to Uppercase | <kbd>**>**</kbd><br> Indent | <kbd>**<**</kbd><br> Unindent | <kbd>**~**</kbd><br> Toggle case of character under cursor |
| <kbd>**Ctrl**</kbd> <kbd>**a**</kbd><br> Increase number under cursor | <kbd>**Ctrl**</kbd> <kbd>**x**</kbd><br> Decrease number under cursor | <kbd>**I**</kbd><br> Insert character, multiple lines | <kbd>**Esc**</kbd><br> Go to Normal mode | <kbd>**j**</kbd><br> Go Down :arrow_down: |
| <kbd>**k**</kbd><br> Go Up :arrow_up: | <kbd>**j**</kbd><br> Go Left :arrow_left: | <kbd>**k**</kbd><br> Go Up :arrow_up: |

</details>

## Replace mode

<details open>
  <summary>Replace Text</summary>
  
|                               |                             |                               |                             |
|:-----------------------------:|:---------------------------:|:-----------------------------:|:---------------------------:|
| <kbd>**Esc**</kbd> Go to Normal mode | <kbd>**Backspace**</kbd> Undo |  |  |

</details>


## Insert mode

<details open>
  <summary>Insert Text</summary>

|                               |                             |                               |                             |
|:-----------------------------:|:---------------------------:|:-----------------------------:|:---------------------------:|
| <kbd>**Ctrl**</kbd> <kbd>**e**</kbd><br> Insert the character which is below the cursor | <kbd>**Ctrl**</kbd> <kbd>**y**</kbd><br> Insert the character which is above the cursor | <kbd>**Ctrl**</kbd> <kbd>**i**</kbd><br>Insert a Tab | <kbd>**Ctrl**</kbd> <kbd>**h**</kbd> OR <kbd>**Backspace**</kbd><br>Delete the character before the cursor |
| <kbd>**Ctrl**</kbd> <kbd>**t**</kbd><br> Add indent in current line | <kbd>**Ctrl**</kbd> <kbd>**d**</kbd><br> Remove indent in current line | <kbd>**Ctrl**</kbd> <kbd>**w**</kbd><br>Delete the word before the cursor | <kbd>**Ctrl**</kbd> <kbd>**u**</kbd><br> Delete characters before the cursor in current line |
| <kbd>**Esc**</kbd><br> Go to Normal mode |  |  |  |

</details>


## History mode

<details open>
  <summary>Backup File Manager</summary>

|                               |                             |                               |                             |
|:-----------------------------:|:---------------------------:|:-----------------------------:|:---------------------------:|
| <kbd>**j**</kbd><br> Go Down :arrow_down: | <kbd>**k**</kbd><br> Go Up :arrow_up: | <kbd>**Enter**</kbd><br> Open Diff | <kbd>**R**</kbd><br> Restore Backup file |
| <kbd>**D**</kbd><br> Delete Backup file | <kbd>**r**</kbd><br> Reload Backup file | <kbd>**g**</kbd> <kbd>**g**</kbd><br> Go to the first line :arrow_up: | <kbd>**G**</kbd><br> Go to the last line :arrow_down: |

</details>


## Diff mode

<details open>
  <summary>Diff viewer</summary>

|                               |                             |                               |                             |
|:-----------------------------:|:---------------------------:|:-----------------------------:|:---------------------------:|
| <kbd>**j**</kbd><br> Go Down :arrow_down: | <kbd>**k**</kbd><br> Go Up :arrow_up: | <kbd>**g**</kbd> <kbd>**g**</kbd><br> Go to the first line :arrow_up: | <kbd>**G**</kbd><br> Go to the last line :arrow_down: |

</details>


## Filer mode

<details open>
  <summary>File Manager</summary>

|                               |                             |                               |                             |
|:-----------------------------:|:---------------------------:|:-----------------------------:|:---------------------------:|
| <kbd>**D**</kbd><br> Delete file | <kbd>**k**</kbd><br> Go Up :arrow_up: | <kbd>**g**</kbd><br> Go to top of list :arrow_up: | <kbd>**G**</kbd><br> Go to the bottom of list :arrow_down: |
| <kbd>**i**</kbd><br> Detail Information | <kbd>**v**</kbd><br> Split window and open file or directory |  |  |

</details>


## Configuration mode
<details open>
  <summary>In Configuration mode</summary>

|                               |                             |                               |                             |
|:-----------------------------:|:---------------------------:|:-----------------------------:|:---------------------------:|
| <kbd>**h**</kbd><br>Go Left :arrow_left: | <kbd>**j**</kbd><br> Go Down :arrow_down: | <kbd>**k**</kbd><br> Go Up :arrow_up: | <kbd>**l**</kbd><br> Go Rigth :arrow_right: |
| <kbd>**g**</kbd> <kbd>**g**</kbd><br> Go to the first line :arrow_up: | <kbd>**G**</kbd><br> Go to the last line :arrow_down: | <kbd>**Enter**</kbd><br> Edit setting | <kbd>**w**</kbd><br> Save the current editor settings to the configuration file |

## Ex mode

<details open>
  <summary>Ex mode</summary>

```number``` - Jump to line number : Example ```:10```  
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

```livereload on``` or ```livereload on``` - Change setting of live reload of configuration file  
```theme themeName``` - Change color theme : Example ```theme dark```  
```tab on``` or ```tab off``` - Change setting to tab line  
```syntax on``` or ```syntax off``` - Change setting to syntax highlighting  
```tabstop number``` - Change setting to tabStop : Exmaple ```tabstop 2```  
```paren on``` or ```paren off``` - Change setting to auto close paren  
```indent on``` or ```indent off``` - Chnage sestting to auto indent  
```linenum on``` or ```linenum off``` - Change setting to dispaly line number  
```statusLine on``` or ```statusLine on``` - Change setting to display stattus bar  
```realtimesearch on``` or ```realtimesearch off``` - Change setting to real-time search   
```deleteparen on``` or ```deleteparen off``` - Change setting to auto delete paren  
```smoothscroll on``` or ```smoothscroll off``` - Change setting to smooth scroll  
```scrollspeed number``` - Set smooth scroll speed : Example ```scrollspeed 10```  
```highlightcurrentword on``` or ```highlightcurrentword off``` - Change setting to highlight other uses of the current word  
```clipboard on``` or ```clipboard off``` - Change setting to system clipboard  
```highlightfullspace on``` or ```highlightfullspace off``` - Change setting to highlight full width space  
```buildonsave on``` or ```buildonsave off``` - Change setting to build on save  
```indentationlines on ``` or ```indentationlines off``` - Change setting to indentation lines  
```showGitInactive on``` or ```showGitInactive off``` - Change status line setting to show/hide git branch name in inactive window  
```noh``` - Turn off highlights  
```icon``` - Setting show/hidden icons in filer mode  
```deleteTrailingSpaces``` - Delete trailing spaces  
```ignorecase``` - Change setting to ignorecase  
```smartcase``` - Change setting to smartcase  
```highlightCurrentLine on``` or ```highlightCurrentLine off``` - Change the highlight setting of the current line  
```build``` - Build the current buffer

```log``` - Open messages log viwer  

```help``` - Open help

```putConfigFile``` - Put a sample configuration file in ~/.config/moe

```run``` or ```Q``` - Quick run

```recent``` - Open recent file selection mode (Only supported on Linux)  

```history``` - Open backup file manager  

```conf``` - Open configuration mode

```debug``` - Open debug mode

</details>

[Go To Top](#table-of-contents)
