#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2023 Shuhei Nogawa                                       #
#                                                                              #
#  This program is free software: you can redistribute it and/or modify        #
#  it under the terms of the GNU General Public License as published by        #
#  the Free Software Foundation, either version 3 of the License, or           #
#  (at your option) any later version.                                         #
#                                                                              #
#  This program is distributed in the hope that it will be useful,             #
#  but WITHOUT ANY WARRANTY; without even the implied warranty of              #
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the               #
#  GNU General Public License for more details.                                #
#                                                                              #
#  You should have received a copy of the GNU General Public License           #
#  along with this program.  If not, see <https://www.gnu.org/licenses/>.      #
#                                                                              #
#[############################################################################]#

import std/[unittest, osproc, strformat, strutils]
import pkg/results
import moepkg/[settings, unicodeext, clipboard]
import utils

import moepkg/platform {.all.}
import moepkg/independentutils {.all.}

proc removeLineEnd(buf: string, tool: ClipboardTool): string =
  case tool:
    of wslDefault, wlClipboard:
      result = buf
      for i in 0 .. 1:
        # Remove two newlines.
        result.stripLineEnd
    else:
      return buf.removeLineEnd

template isToolAvailable(tool: ClipboardTool): bool =
  case tool:
    of xsel: isXselAvailable()
    of xclip: isXclipAvailable()
    of wlClipboard: isWlClipboardAvailable()
    of wslDefault: isWsl()
    else: false

template getClipboardBuffer(tool: ClipboardTool): string =
  case tool:
    of xsel: getXselBuffer()
    of xclip: getXclipBuffer()
    of wlClipboard: getWlClipboardBuffer()
    of wslDefault: getWslDefaultBuffer()
    else: ""

template clearClipboard(tool: ClipboardTool) =
  case tool
    of xsel: assert clearXsel()
    of xclip: assert clearXclip()
    of wlClipboard: assert clearWlClipboard()
    of wslDefault: assert clearWslDefaultClipboard()
    else: assert false

template runClipboardSendTests(tool: ClipboardTool) =
  test "Runes":
    if not isToolAvailable(tool):
      skip()
    else:
      clearClipboard(tool)

      const Buffer = ru"abc"
      check sendToClipboard(Buffer, tool).isOk

      let buf = getClipboardBuffer(tool).removeLineEnd(tool)
      check buf == $Buffer

  test "Lines":
    if not isToolAvailable(tool):
      skip()
    else:
      clearClipboard(tool)

      const Buffer = @["abc", "def"].toSeqRunes
      check sendToClipboard(Buffer, tool).isOk

      let buf = getClipboardBuffer(tool).removeLineEnd(tool)
      check buf == Buffer.toString.removeLineEnd

  test "Only back quotes":
    if not isToolAvailable(tool):
      skip()
    else:
      const Buffer = @["`````"].toSeqRunes
      check sendToClipboard(Buffer, tool).isOk

      let buf = getClipboardBuffer(tool).removeLineEnd(tool)
      check buf == Buffer.toString.removeLineEnd

template runClipboardGetTests(tool: ClipboardTool) =
  test "Runes":
    if not isToolAvailable(tool):
      skip()
    else:
      clearClipboard(tool)

      const Buffer = ru"abc"
      assert sendToClipboard(Buffer, tool).isOk

      let buf = getFromClipboard(tool).get
      check buf == Buffer

  test "Lines":
    if not isToolAvailable(tool):
      skip()
    else:
      clearClipboard(tool)

      const Buffer = @["abc", "def"].toSeqRunes
      assert sendToClipboard(Buffer, tool).isOk

      let buf = getFromClipboard(tool).get
      check buf == "abc\ndef".toRunes

suite fmt"clipboard: Send to clipboad (xsel)":
  runClipboardSendTests(ClipboardTool.xsel)

suite fmt"clipboard: Send to clipboad (xclip)":
  runClipboardSendTests(ClipboardTool.xclip)

suite fmt"clipboard: Send to clipboad (wl-clipboard)":
  runClipboardSendTests(ClipboardTool.wlClipboard)

suite fmt"clipboard: Send to clipboad (WSL)":
  runClipboardSendTests(ClipboardTool.wslDefault)

suite fmt"clipboard: Get from clipboad (xsel)":
  runClipboardGetTests(ClipboardTool.xsel)

suite fmt"clipboard: Get from clipboad (xclip)":
  runClipboardGetTests(ClipboardTool.xclip)

suite fmt"clipboard: Get from clipboad (wl-clipboad)":
  runClipboardGetTests(ClipboardTool.wlClipboard)

suite fmt"clipboard: Get from clipboad (WSL)":
  runClipboardGetTests(ClipboardTool.wslDefault)
