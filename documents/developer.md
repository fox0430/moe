# Developer documentation

## How to debug moe 

### Using logger
You can use the logger.
Log files are written to the temp dir (`/tmp/moe/logs`).
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
cat /tmp/moe/logs/2023-10-24T05:42:17+09:00/moe.log
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
