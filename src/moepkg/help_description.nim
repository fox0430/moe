#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2026 Shuhei Nogawa                                       #
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

## Structured description type for `HelpEntry` and `SetOptionSpec`.
##
## A description is a sequence of segments: plain text or inline code. The
## TUI help (`help_generator.nim`) and the `:set` completion popup
## (`command_completion.nim`) render the plain-text form; the howtouse.md
## tables (`help_markdown.nim`) render the markdown form with code spans
## wrapped in backticks.
##
## Source data still authors descriptions as ordinary string literals with
## markdown backticks (e.g. `"e.g. \`:10\`"`). Each module that constructs
## `HelpEntry` / `SetOptionSpec` / `HelpGroup` literals declares its own
## *private* `converter toDescription(s: string): Description` via the
## `descriptionFromStringConverter` template below. The converter must
## stay private (no `*`) and module-local — exporting it (or putting it
## in this shared module without the template indirection) leaks the
## implicit `string → Description` coercion into transitive importers
## and breaks unrelated overload resolution (e.g.
## `writeLine(stderr, "...")` in `emergency.nim`).
##
## Escape syntax in text segments: `\\` is a literal backslash, and `` \` ``
## is a literal backtick (otherwise consumed as a code-span delimiter).
## Any other `\X` sequence is passed through verbatim (so existing data
## with stray backslashes round-trips). Code segments are taken raw
## between backticks — no escape inside them; if a code span needs to
## contain a literal backtick, write the surrounding text as
## ` \`literal\` ` instead.

type
  DescSegmentKind* = enum
    dskText ## Plain text passed through to all renderers verbatim.
    dskCode ## Inline code; backtick-wrapped in markdown, unwrapped in plain text.

  DescSegment* = object
    kind*: DescSegmentKind
    text*: string

  Description* = seq[DescSegment]

proc parseDescription*(s: string): Description =
  ## Split `s` on paired backticks into alternating text/code segments.
  ##
  ## Recognized escapes in text mode: `\\` → `\`, `` \` `` → `` ` ``.
  ## Any other `\X` keeps both characters as literal text. Unmatched
  ## backticks (no closing partner) are also treated as literal text so
  ## the original source round-trips through plain-text rendering.
  var i = 0
  var buf = ""
  while i < s.len:
    let c = s[i]
    if c == '\\' and i + 1 < s.len and s[i + 1] in {'\\', '`'}:
      buf.add s[i + 1]
      i += 2
    elif c == '`':
      var j = i + 1
      while j < s.len and s[j] != '`':
        inc j
      if j < s.len:
        if buf.len > 0:
          result.add DescSegment(kind: dskText, text: buf)
          buf = ""
        result.add DescSegment(kind: dskCode, text: s[i + 1 ..< j])
        i = j + 1
      else:
        buf.add c
        inc i
    else:
      buf.add c
      inc i
  if buf.len > 0:
    result.add DescSegment(kind: dskText, text: buf)

template descriptionFromStringConverter*() =
  ## Emit a *private* `string → Description` converter in the calling
  ## module's scope. Invoke this once at module top-level before any
  ## `description: "literal"` initializer for `HelpEntry`,
  ## `SetOptionSpec`, or `HelpGroup`. Keeping the converter private
  ## prevents it from propagating into modules that import (transitively
  ## or otherwise) the table-defining module — global propagation
  ## confuses overload resolution for `varargs[Ty, $]` builtins like
  ## `writeLine`.
  converter toDescriptionImpl(s: string): Description {.used.} =
    parseDescription(s)

proc toPlainText*(d: Description): string =
  ## Render for terminal contexts (TUI help, completion popup). Drops the
  ## markdown markers; only segment text survives.
  for seg in d:
    result.add seg.text

proc appendCellChar(buf: var string, c: char) =
  ## Per-character escape shared by `escapeMdCell` and the text-segment
  ## branch of `toMarkdownCell`. Handles the chars that would otherwise
  ## corrupt a single GFM table cell: `|` ends the cell, `\` escapes the
  ## following char, and embedded newlines split the row.
  case c
  of '\\':
    buf.add "\\\\"
  of '|':
    buf.add "\\|"
  of '\n', '\r':
    buf.add ' '
  else:
    buf.add c

proc escapeMdCell*(s: string): string =
  ## Escape `s` for safe inclusion as a single markdown table cell.
  ## Used by `help_markdown.nim`'s `kbd()` helper to wrap individual
  ## key-binding tokens (`<kbd>**\\**</kbd>`, `<kbd>**|**</kbd>`) without
  ## tripping the table parser. Backticks are *not* escaped here — they
  ## are consumed structurally by `parseDescription`/`toMarkdownCell`,
  ## and kbd tokens that contain a literal `` ` `` would render fine as
  ## a code span inside the bolded label anyway.
  result = newStringOfCap(s.len)
  for c in s:
    appendCellChar(result, c)

proc toMarkdownCell*(d: Description): string =
  ## Render for a single GFM table cell: code segments wrapped in
  ## backticks, text segments escaped via `appendCellChar` for the usual
  ## cell-special characters, plus literal `` ` `` escaped as `` \` `` so
  ## an escaped-backtick text segment doesn't reopen a code span.
  ## Code segments are emitted verbatim — `parseDescription` never
  ## puts backticks inside a `dskCode` segment.
  for seg in d:
    case seg.kind
    of dskText:
      for c in seg.text:
        if c == '`':
          result.add "\\`"
        else:
          appendCellChar(result, c)
    of dskCode:
      result.add '`'
      result.add seg.text
      result.add '`'

proc addStr*(d: var Description, suffix: string) =
  ## Append a string suffix as a parsed `Description`. Used by
  ## `help_markdown.renderSetOptionRows` to splice the alias annotation
  ## (`" (alias: \`hcc\`, \`nohcc\`)"`) onto a spec description without
  ## flattening either side to a string first. Not named `add` so it
  ## doesn't shadow `system.add(var seq[T], T)`, which kept getting
  ## confused with the converter during overload resolution and broke
  ## unrelated `writeLine(file, str)` call sites in transitively-importing
  ## modules.
  for seg in parseDescription(suffix):
    d.add seg
