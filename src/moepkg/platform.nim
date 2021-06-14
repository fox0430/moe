import osproc, strutils

type Platform* = enum
  linux, wsl, mac, other

proc initPlatform(): Platform =
  if defined linux:
    if execProcess("uname -r").contains("microsoft"):
      result = Platform.wsl
    else: result = Platform.linux
  elif defined macosx:
    result = Platform.mac
  else:
    result = Platform.other

let CURRENT_PLATFORM* = initPlatform()
