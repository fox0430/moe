## Exiting
check command bar  

```:w``` - write file  
```:q``` - quit  
```:wq``` - write file and quit  
```:q!``` - force quit  

## Normal mode
```h``` - ←  
```j``` - ↓  
```k``` - ↑  
```l``` - →  
```+``` - same as j  
```-``` - same as k  
```w``` - move forwards to the start of a word  
```e``` - move forwards to the end of a word  
```b``` - move backwards to the start of a word  
```Page Up``` - page up  
```Page Down``` - page down  
```gg``` - move to the first line  
```G``` - move to the last line  
```0``` - (zero) first of the line  
```$``` - end of the line  
```^``` - same as 0  

```u``` - undo  
```Ctrl-r``` - redo  

```v``` - start visual mode  
```Ctrl-v``` start visual block mode  
```r``` - start replace mode  
```i``` - start insert mode  
```o``` - insert a new line and start insert mode  
```a``` - append after the cursor and start insert mode  
```r``` - replace a character at the cursor  
```A``` - same as $a  
```I``` - same as 0a  

```>``` - indent  
```<``` - unindent

```dd``` - delete(cut) a line  
```x``` - delete(cut) current character  

```yy``` - copy a line  
```p``` - paste the clipboard  

```n``` - repeat search in same direction  
```N``` - repeat search in opposite direction  

```f``` - jump to next occurrence
```F``` - jump to previous occurence

```Ctrl-k``` - move next window  
```Ctrl-j``` - move prev window  

```z.``` - center the screen on the cursor  
```zt``` - scroll the screen so the cursor is at the top  
```zb``` - scroll the screen so the cursor is at the bottom  

```ZZ``` - write current file and exit  
```ZQ``` - same as ":q!"  

```/``` - search text  
```:``` - start ex mode  

## Visual mode
```d ```or ```x``` - delete(cut) text  
```y``` - copy text  
```r``` - replace character  

```>``` - indent  
```<``` - unindent  

```Esc``` - start normal mode  

## Replace mode
```Esc``` - start normal mode  

Insert mode
```Esc``` - start normal mode  

## Filer mode
```D``` - delete file  
```g``` - go to top of list  
```G``` - go to last of list  
```i``` - detail information  

## Ex mode
```:!``` shell command - shell command execution  

```:e``` filename - open file  

```/keyword``` - search text, file or directory  

```:%s/keyword1/keyword2/``` - replace text (normal mode only)  

```ls``` - Display all buffer  
```bprev``` - Switch to the previous buffer  
```bnext``` - Switch to the next buffer  
```bfirst``` - Switch to the first buffer  
```blast``` - Switch to the last buffer  

```vs``` - Split window  
