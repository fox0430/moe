import unittest
import moepkg/[settings, unicodeext]
include moepkg/[clipboard]

suite "Clipboard":
  test "Send the text to the clipboard":
    const buffer = @[ru "abc"]
    sendToClipboard(buffer, settings.ClipboardToolOnLinux.xsel)

    let r = execCmdEx("xsel -o")
    check r.output == "abc\n"

  test "Send the text to the clipboard 2":
    const buffer = @[ru "abc", ru "def"]
    sendToClipboard(buffer, settings.ClipboardToolOnLinux.xsel)

    let r = execCmdEx("xsel -o")
    check r.output == "abc\ndef\n"
