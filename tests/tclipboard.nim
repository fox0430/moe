import unittest
import moepkg/[settings, unicodeext]
include moepkg/[clipboard, platform]

proc initRegister(
  buffer: seq[Rune],
  settings: EditorSettings): register.Registers {.compiletime.} =

  result.addRegister(buffer, settings)

proc initRegister(
  buffer: seq[seq[Rune]],
  settings: EditorSettings): register.Registers {.compiletime.} =

  result.addRegister(buffer, settings)

suite "Editor: Send to clipboad":
  test "Send string to clipboard 1 (xsel)":
    const
      buffer = ru "Clipboard test"
      tool = ClipboardToolOnLinux.xsel
    let settings = initEditorSettings()

    let registers = initRegister(buffer, settings)

    let p = initPlatform()
    if (p == Platforms.linux or
        p == Platforms.wsl):
      let
        cmd = if p == Platforms.linux:
                execCmdEx("xsel")
              else:
                # On the WSL
                execCmdEx("powershell.exe -Command Get-Clipboard")
        (output, exitCode) = cmd

      check exitCode == 0
      if p == Platforms.linux:
        check output[0 .. output.high - 1] == $buffer
      else:
        # On the WSL
        check output[0 .. output.high - 2] == $buffer

  test "Send string to clipboard 1 (xclip)":
    const
      str = ru"Clipboard test"
      registers = initRegister(str)
      tool = ClipboardToolOnLinux.xclip

    let platform = editorstatus.initPlatform()
    registers.sendToClipboad(platform, tool)

    if (platform == editorstatus.Platform.linux or
        platform == editorstatus.Platform.wsl):
      let
        cmd = if platform == editorstatus.Platform.linux:
                execCmdEx("xclip -o")
              else:
                # On the WSL
                execCmdEx("powershell.exe -Command Get-Clipboard")
        (output, exitCode) = cmd

      check exitCode == 0
      if platform == editorstatus.Platform.linux:
        check output[0 .. output.high - 1] == $str
      else:
        # On the WSL
        check output[0 .. output.high - 2] == $str

  test "Send string to clipboard 2 (xsel)":
    const
      str = ru"`````"
      registers = initRegister(str)
      tool = ClipboardToolOnLinux.xsel

    let platform = editorstatus.initPlatform()
    registers.sendToClipboad(platform, tool)

    if (platform == editorstatus.Platform.linux or
        platform == editorstatus.Platform.wsl):
      let
        cmd = if platform == editorstatus.Platform.linux:
                execCmdEx("xsel")
              else:
                # On the WSL
                execCmdEx("powershell.exe -Command Get-Clipboard")
        (output, exitCode) = cmd

      check exitCode == 0
      if platform == editorstatus.Platform.linux:
        check output[0 .. output.high - 1] == $str
      else:
        # On the WSL
        check output[0 .. output.high - 2] == $str

  test "Send string to clipboard 2 (xclip)":
    const
      str = ru"`````"
      registers = initRegister(str)
      tool = ClipboardToolOnLinux.xclip

    let platform = editorstatus.initPlatform()
    registers.sendToClipboad(platform, tool)

    if (platform == editorstatus.Platform.linux or
        platform == editorstatus.Platform.wsl):
      let
        cmd = if platform == editorstatus.Platform.linux:
                execCmdEx("xclip -o")
              else:
                # On the WSL
                execCmdEx("powershell.exe -Command Get-Clipboard")
        (output, exitCode) = cmd

      check exitCode == 0
      if platform == editorstatus.Platform.linux:
        check output[0 .. output.high - 1] == $str
      else:
        # On the WSL
        check output[0 .. output.high - 2] == $str

  test "Send string to clipboard 3 (xsel)":
    const
      str = ru"$Clipboard test"
      registers = initRegister(str)
      tool = ClipboardToolOnLinux.xsel

    let platform = editorstatus.initPlatform()
    registers.sendToClipboad(platform, tool)

    if (platform == editorstatus.Platform.linux or
        platform == editorstatus.Platform.wsl):
      let
        cmd = if platform == editorstatus.Platform.linux:
                execCmdEx("xsel")
              else:

                # On the WSL
                execCmdEx("powershell.exe -Command Get-Clipboard")
        (output, exitCode) = cmd

      check exitCode == 0
      if platform == editorstatus.Platform.linux:
        check output[0 .. output.high - 1] == $str
      else:
        # On the WSL
        check output[0 .. output.high - 2] == $str

  test "Send string to clipboard 3 (xclip)":
    const
      str = ru"$Clipboard test"
      registers = initRegister(str)
      tool = ClipboardToolOnLinux.xclip

    let platform = editorstatus.initPlatform()
    registers.sendToClipboad(platform, tool)

    if (platform == editorstatus.Platform.linux or
        platform == editorstatus.Platform.wsl):
      let
        cmd = if platform == editorstatus.Platform.linux:
                execCmdEx("xclip -o")
              else:

                # On the WSL
                execCmdEx("powershell.exe -Command Get-Clipboard")
        (output, exitCode) = cmd

      check exitCode == 0
      if platform == editorstatus.Platform.linux:
        check output[0 .. output.high - 1] == $str
      else:
        # On the WSL
        check output[0 .. output.high - 2] == $str


