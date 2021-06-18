# Developer documentation

## How to debug moe 
### printf debug
You can use ```echo()``` in moe. But, need to exit ncurses before ```echo()```.
Exit using ```exitUi()``` or ```ncurses.endwin()```.
And, ncurses UI is auto restart when printing ncurses UI (You don't need to execute ```startUI()```).

Example

```Nim
proc initEditor(): EditorStatus =
  let parsedList = parseCommandLineOption(commandLineParams())

  defer: exitUi()

  startUi()

  ##### Important! #####
  exitUi()
  echo "debug"

  result = initEditorStatus()
  result.loadConfigurationFile
  result.timeConfFileLastReloaded = now()
  result.changeTheme
```

Please use :! or quit moe to check the output.

### Using log viewer
You can use the log in moe. 

Example

```Nim
proc normalMode*(status: var EditorStatus) =
  if not status.settings.disableChangeCursor:
    changeCursorType(status.settings.normalModeCursor)

  ##### Write to log #####
  status.messageLog.add(($status.settings.normalModeCursor).toRunes)
```

You can check log in Log viewer (```:log``` command).

## Debug mode
moe is build in Debug mode. Debug mode can be start with ```:debug``` command.

Screenshot
![moe](https://user-images.githubusercontent.com/15966436/108370845-71580780-7240-11eb-86cf-2c9ef8fa1a57.png)

## Code map

### ```src/moe.nim```
When moe start, Start ncurses. Next, Initialize settings and load the configuration file if existing.
And load the text file if got an argument. At last, Starting editor main loop.

### ```src/moepkg/editorstatus.nim```
Editor initializing, add a buffer, update highlighting and create, remove, resize and update view and window, etc...

### ```src/moepkg/editorview.nim```
Update and move editor view.

### ```src/moepkg/ui.nim```
Control the terminal (console).

### ```src/moepkg/bufferstatus.nim```
Define BufferStatus, Mode and SelectArea.

### ```src/moepkg/gapbuffer.nim```
Implementation of Gap buffer.

### ```src/moepkg/movement.nim```
Many editor movement procs (Ex. move right, move to the end of the line, move to the next word, etc...).
theses procs are used in many modes.

### ```src/moepkg/editor.nim```
Many procs for editing text (Ex. Insert/delete characters, undo/redo, delete a word, etc...).

### ```src/moepkg/settings.nim```
Define EditorSettings, load and validate the configuration file.

### ```src/moepkg/color.nim```
Define Color, EditorColorPair, Theme.

### ```src/moepkg/syntax```
Create syntax highlighting in some languages.

### ```src/moepkg/fileutils.nim```
Utils for files.

### ```src/moepkg/unicodetext.nim```
Extend unicode module of Nim.

### ```src/moepkg/messages.nim```
Messages displayed in the command line window.

### ```src/moepkg/window.nim```
Management of the main window node.

### ```src/moepkg/tabline.nim```
Write Tab line.

### ```src/moepkg/normalmode.nim```
Normal mode loop and Normal mode commands.

### ```src/moepkg/insert.nim```
Insert mode loop and Insert mode commands.

### ```src/moepkg/exmode.nim```
Ex (command line) mode loop and Ex mode commands.

### ```src/moepkg/help.nim```
Help in moe (```:help``` command).

### ```src/moepkg/visualmode.nim```
Visual/Visual block mode loop and Visual/Visual block mode commands.

### ```src/moepkg/undoredostack.nim```
undo/redo utils

### ```src/moepkg/suggestionwindow.nim```
Suggestion (pop-up) window for general auto-complete in insert mode.

### ```src/moepkg/generalautocomplete.nim```
Make dictonaly for general auto-complete in insert mode.

### ```src/moepkg/statusline.nim```
Write Status line

### ```src/moepkg/search.nim```
Search utils for normal mode.

### ```src/moepkg/quickrun.nim```
Implementation of QuickRun.

### ```src/moepkg/replacemode.nim```
Replace mode loop and Replace mode commands.

### ```src/moepkg/logviwer.nim```
moe's log viewer. (```:log```)

### ```src/moepkg/historymanager.nim```
History mode loop and History mode commands. (```:history```)
History mode is the manager of the auto-backup files.

### ```src/moepkg/diffviewer.nim```
Diff mode loop and Diff mode commands.
Diff mode can start in History mode. And, it shows the difference between the backup file and the current buffer.

### ```src/moepkg/recentfilemode.nim```
Recent mode loop and commands.
Recent mode is can select recently opened files.
This mode is GNU/Linux only supported.

### ```src/moepkg/highlight.nim```
Update syntax highlighting.

### ```src/moepkg/filermode.nim```
Filer mode loop and commands.

### ```src/moepkg/debugmode.nim```
Debug mode loop and commands. (```:debug```)

### ```src/moepkg/cursor.nim```
Update cursor position.

### ```src/moepkg/configmode.nim```
Configration mode loop and commands. (```conf```:)

### ```src/moepkg/cmdlineoption.nim```
Parse command line arguments and write help in command line.

### ```src/moepkg/build.nim```
Implementation of Build on save.

### ```src/moepkg/commandview.nim```
Write command line in moe.

### ```src/moepkg/backup.nim```
Implementation of Automatic backups.

### ```src/moepkg/buffermanager.nim```
Buffer manager mode and commands. (```:buf```)

### ```src/moepkg/register.nim```
Definition of the registers and utils for the register.

###  ```src/moepkg/clipboard.nim```
Utils for the clipboard.

###  ```src/moepkg/platform.nim```
Check and definition the platform.
