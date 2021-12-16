import std/[osproc, strutils]

type Platforms* = enum
  linux, wsl, mac, freebsd, openbsd, other

proc initPlatform(): Platforms =
  if defined linux:
    if execProcess("uname -r").contains("microsoft"):
      result = Platforms.wsl
    else: result = Platforms.linux
  elif defined macosx:
    result = Platforms.mac
  elif defined freebsd:
    result = Platforms.freebsd
  elif defined openbsd:
    result = Platforms.openbsd
  else:
    result = Platforms.other

let CURRENT_PLATFORM* = initPlatform()
