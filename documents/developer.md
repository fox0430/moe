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

### Using logger
You can use the logger.
Log files are written to the cache dir (`~/.cache/moe/logs`).
You have to import `srd/logger`.

Example

```Nim
import std/[os, times, logging]
import moepkg/[ui, bufferstatus, editorstatus, cmdlineoption, mainloop]

##### Important #####
import std/logging

.
.
.

proc initEditor(): EditorStatus =
  let parsedList = parseCommandLineOption(commandLineParams())

  defer: exitUi()

  startUi()

  ##### Important! #####
  debug "debug"

  result = initEditorStatus()
  result.loadConfigurationFile
  result.timeConfFileLastReloaded = now()
  result.changeTheme
```

```
cat ~/.cache/moe/logs/2023-01-13T05:29:04+09:00.log
DEBUG debug
```

### Using log viewer
You can use the log in moe. 
This is not written to a file.

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

### ```src/moepkg/mainloop.nim```
Editor main loops for main window and command line window.

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
Main module for the Normal mode.

### ```src/moepkg/insert.nim```
Main module for the insert mode.

### ```src/moepkg/exmode.nim```
Main module for the Ex (command line) mode. 

### ```src/moepkg/help.nim```
Help in moe (```:help``` command).

### ```src/moepkg/helputils.nim```
A sentence for the help.

### ```src/moepkg/visualmode.nim```
Main module for Visual and Visual block modes.

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
Main module for the QuickRun mode.

### ```src/moepkg/replacemode.nim```
Main module for the replace mode.

### ```src/moepkg/logviwer.nim```
Main module for the log mode (Log viewer).
The log mode can be started with `:log` command.

### ```src/moepkg/backupmanager.nim```
Main module for the backup mode (Backup manger).
Backup manger is the manager of the auto-backup files.
The backup mode can be started with `:backup` command.

### ```src/moepkg/diffviewer.nim```
Main module for the diff mode.
Diff mode can start in History mode.
And, it shows the difference between the backup file and the current buffer.

### ```src/moepkg/recentfilemode.nim```
Main module for the recent mode.
Recent mode is can select recently opened files.
This mode is GNU/Linux only supported.
The configuration mode can be started with `:recent` command.

### ```src/moepkg/highlight.nim```
Update syntax highlighting.

### ```src/moepkg/filermode.nim```
Main module for the filer mode.

### ```src/moepkg/filermodeutils.nim```
Tools for the filer mode.

### ```src/moepkg/debugmode.nim```
Main module for the debug mode.

### ```src/moepkg/debugmodeutils.nim```
Tools for the debug mode.

### ```src/moepkg/cursor.nim```
Update cursor position.

### ```src/moepkg/configmode.nim```
Main module for the configuration mode.
The configuration mode can be started with `:conf` command.

### ```src/moepkg/cmdlineoption.nim```
Parse command line arguments and write help in command line.

### ```src/moepkg/build.nim```
Implementation of Build on save.

### ```src/moepkg/commandline.nim```
Tools for the command line (window). 

### ```src/moepkg/commandlineutils.nim```
Helper for the command line (window). 

### ```src/moepkg/backup.nim```
Implementation of Automatic backups.

### ```src/moepkg/buffermanager.nim```
Main module for the buffer mode (Buffer manager).
The buffer mode can be started with `:buf` command.

### ```src/moepkg/register.nim```
Definition of the registers and utils for the register.

###  ```src/moepkg/clipboard.nim```
Utils for the clipboard.

###  ```src/moepkg/platform.nim```
Check and definition the platform.

###  ```src/moepkg/popupwindow.nim```
Popup window.

### ```src/moepkg/bufferhighlight.nim```
Highlighting tools for buffers. (Current words, search results, etc...)
