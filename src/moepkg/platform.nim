import osproc, strutils

type Platforms* = enum
  linux, wsl, mac, other

proc initPlatform(): Platforms =
  if defined linux:
    if execProcess("uname -r").contains("microsoft"):
      result = Platforms.wsl
    else: result = Platforms.linux
  elif defined macosx:
    result = Platforms.mac
  else:
    result = Platforms.other

let CURRENT_PLATFORM* = initPlatform()
