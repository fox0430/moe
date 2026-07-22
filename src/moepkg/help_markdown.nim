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

## Runtime markdown rendering for `HelpEntry` / `HelpGroup` data, used by
## `tools/gen_howtouse_docs.nim` to regenerate `documents/howtouse.md`.
##
## The companion `help_generator.nim` renders the same `HelpEntry` data into
## TUI-formatted plain text (consumed by `help_viewer.nim`'s
## `HelpSentences`). This module is a parallel renderer that emits GitHub
## flavored markdown tables with `<kbd>` wrapping. It does not participate
## in the TUI help text and is intentionally kept out of `HelpSentences` so
## that the editor binary is not pulled into doc-generation concerns.

import std/[options, strutils]

import command_line_commands, help_description, help_generator, setting_options

export help_description.escapeMdCell

const
  SpecialKeys = [
    # Multi-word / multi-char tokens that must be matched as a single unit
    # before per-character expansion. Order does not matter — lookup is
    # whole-token equality, not longest-prefix. `Any key` is the canonical
    # form produced by `tokenizeKey`'s normalization; source data using
    # `any` / `any key` is rewritten before lookup, so only the lowercase-`k`
    # variant needs to be in this list.
    "Page Up", "Page Down", "Any key", "Backspace", "Enter", "Space", "Tab", "Escape",
    "Esc", "ESC", "Home", "End", "Up", "Down", "Left", "Right", "Ctrl", "Alt", "Shift",
    "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12",
  ]

  KbdTableHeader = "| Keys | Description |\n|:---|:---|\n"

  CommandTableHeader = "| Command | Description |\n|:---|:---|\n"

  ExitingHelpNames =
    @["w", "q", "wq", "q!", "qa", "wqa", "qa!", "w!", "wq!", "wqa!", "cq"]
  ## Hand-curated order matching the existing howtouse.md row sequence.
  ## `help_generator.nim` ships a slightly different list for TUI help; the
  ## divergence is intentional — TUI help groups by action, the markdown
  ## doc groups by user-discoverability (basic → forced → window-scoped).
  CommandModeHeadNames = @[
    "bg", "man", "e", "ene", "new", "vnew", "delete", "ls", "bprev", "bnext", "bfirst",
    "blast", "bd", "vs", "sp", "only", "theme", "noh", "stripwhitespace",
  ]

  CommandModeTailNames = @[
    "build", "lspfold", "lspformat", "log", "lsplog", "lsprestart",
    "lspcallhierarchyincoming", "lspcallhierarchyoutgoing", "help", "putconfigfile",
    "moerc", "quickrun", "recent", "backup", "config", "debug", "filetree", "jump",
    "terminal", "changes", "bookmarks", "conflictnext", "conflictprev",
  ]

  RuntimeKeyMapNames = @[
    "nmap", "imap", "vmap", "rmap", "cmap", "map", "nunmap", "iunmap", "vunmap",
    "runmap", "cunmap", "unmap", "nmapclear", "imapclear", "vmapclear", "rmapclear",
    "cmapclear", "mapclear",
  ]

  AllHowtouseHelpNames*: seq[string] =
    ExitingHelpNames & CommandModeHeadNames & CommandModeTailNames & RuntimeKeyMapNames
    ## Union of every command name emitted into howtouse.md by the
    ## *command-line* section renderers above (Exiting / CommandMode /
    ## RuntimeKeyMap). Exposed so the sync test can verify that every
    ## `CommandLineCommandSpec` carrying `helpEntries` ends up in at least
    ## one section — a missed name list entry would otherwise drop the new
    ## command silently from the markdown doc.
    ##
    ## The mode-table renderers (`renderNormalModeTable` …
    ## `renderTerminalNormalTable`, `renderRegisterTable`) consume the
    ## `HelpGroup` constants in `help_generator.nim` directly, so they
    ## share their source of truth with the TUI help viewer and are not
    ## part of this coverage union.

proc longestSpecialKeyAt(s: string, i: int): int =
  ## Length of the longest `SpecialKeys` entry that matches `s` starting at
  ## index `i`, or 0 when none matches. The match must sit at word
  ## boundaries on both ends (start/end of string, space, or hyphen) so
  ## `Ctrl` doesn't greedily consume e.g. `xCtrly` (no current data, but
  ## defensive — the greedy-scan caller in `tokenizeKey` only invokes this
  ## at positions just after a space/hyphen, but a future caller without
  ## that invariant would otherwise mis-tokenize).
  if i > 0 and s[i - 1] notin {' ', '-'}:
    return 0
  for k in SpecialKeys:
    if k.len <= result:
      continue
    if i + k.len > s.len:
      continue
    if s[i ..< i + k.len] != k:
      continue
    let endPos = i + k.len
    if endPos < s.len and s[endPos] notin {' ', '-'}:
      continue
    result = k.len

proc tokenizeKey*(syntax: string): seq[string] =
  ## Split a single key-binding sequence (no ` or ` alternation) into the
  ## tokens that should each become a `<kbd>` element. Tokens marked in
  ## `SpecialKeys` (`Ctrl`, `Page Up`, `Esc`, `Any key`, …) are preserved
  ## whole; modifier prefixes (`Ctrl-u`, `Shift-F4`) split on the hyphen;
  ## everything else is expanded character-by-character so vim-style
  ## concatenations like `gg`, `ciw`, `:cq` produce one token per key the
  ## user actually presses.
  ##
  ## The `any` placeholder used in source data (`"q any"`, `"yt any"`,
  ## `"@ any"`) is normalized to the canonical `Any key`.
  # Normalize the `any` / `any key` placeholders to the canonical SpecialKey
  # form so the greedy scan below finds them via the `Any key` entry.
  # `replace(" any", ...)` would over-match (` anything` → ` Any keything`),
  # so each substitution is scoped to a token boundary: leading space on
  # both sides, plus trailing space or string-end on the right.
  var s = syntax.replace(" any key", " Any key")
  s = s.replace(" any ", " Any key ")
  if s.endsWith(" any"):
    s = s[0 ..< s.len - 4] & " Any key"
  if s == "any key":
    s = "Any key"
  if s == "any":
    return @["Any key"]

  # Greedy scan: at each position, prefer the longest matching SpecialKey;
  # then a single character. Replaces the older split-by-space approach,
  # which silently broke multi-word SpecialKeys (`Page Up` was split into
  # `[P, a, g, e, Up]`).
  var i = 0
  while i < s.len:
    if s[i] == ' ':
      inc i
      continue
    let m = longestSpecialKeyAt(s, i)
    if m > 0:
      result.add s[i ..< i + m]
      i += m
      # A hyphen right after a modifier (`Ctrl-`, `Alt-`, `Shift-`) joins
      # the modifier to its tail in the source syntax. Drop it so the
      # tail (`u`, `F4`, …) tokenizes on the next iteration as its own
      # SpecialKey or as a single character.
      if i < s.len and s[i] == '-':
        inc i
      continue
    result.add $s[i]
    inc i

proc kbd(token: string): string =
  ## "h" → "<kbd>**h**</kbd>". The token is run through `escapeMdCell` so
  ## that `\` and `|` survive the markdown parser intact: a literal `\`
  ## inside `**...**` would otherwise pair with the trailing `*` as an
  ## escape (`**\**` renders as `*<em>*</em>`, dropping the backslash),
  ## and a `|` would end the table cell early. `**...**` bold markers
  ## stay outside the escape so they remain active.
  "<kbd>**" & escapeMdCell(token) & "**</kbd>"

proc renderKbdSegment(syntax: string): string =
  ## Render one alternation segment as space-separated `<kbd>` tokens.
  let toks = tokenizeKey(syntax)
  var parts: seq[string] = @[]
  for t in toks:
    parts.add kbd(t)
  parts.join(" ")

proc renderKbdKeysCell*(syntax: string): string =
  ## Render the Keys-column cell for kbd-style mode tables (Normal, Visual,
  ## Exiting …). Splits on the ` or ` alternation separator and joins each
  ## segment with ` OR ` (uppercase, mirroring the existing howtouse.md
  ## convention).
  var segments: seq[string] = @[]
  for seg in syntax.split(" or "):
    segments.add renderKbdSegment(seg)
  segments.join(" OR ")

proc renderBacktickCell*(syntax: string): string =
  ## Render the Command-column cell for command-mode tables. Wraps the
  ## syntax in backticks and handles ` or ` alternations by wrapping each
  ## side separately: `"bd or bd number"` → `` `bd` or `bd number` ``.
  var segments: seq[string] = @[]
  for seg in syntax.split(" or "):
    segments.add "`" & seg & "`"
  segments.join(" or ")

proc renderKbdHelpGroupRow(e: HelpEntry): string =
  "| " & renderKbdKeysCell(e.syntax) & " | " & toMarkdownCell(e.description) & " |\n"

proc renderKbdHelpGroup*(g: HelpGroup): string =
  ## Render a `HelpGroup` as a complete kbd-style markdown table (header +
  ## one row per entry). `HelpGroup.minWidth` is intentionally ignored —
  ## that field is a TUI padding hint for `help_generator.renderGroup` and
  ## has no equivalent in GFM tables.
  result = KbdTableHeader
  for e in g.entries:
    result.add renderKbdHelpGroupRow(e)

proc renderCommandRow(e: HelpEntry): string =
  "| " & renderBacktickCell(e.syntax) & " | " & toMarkdownCell(e.description) & " |\n"

proc lookupHelpEntries(name: string): seq[HelpEntry] =
  ## Runtime equivalent of the `{.compileTime.}` `helpEntriesFor` helper in
  ## `help_generator.nim`. Look up a command-line spec by name and return
  ## its `helpEntries`, or `@[]` when the spec has none.
  let s = findCommandLineCommand(name)
  if s.isSome:
    s.get.helpEntries
  else:
    @[]

# Exiting

proc renderExitingTable*(): string =
  result = KbdTableHeader
  for name in ExitingHelpNames:
    for e in lookupHelpEntries(name):
      result.add renderKbdHelpGroupRow(e)

# Command mode (commands + set options + lsp/build/etc.)

proc renderSetOptionRows(): string =
  ## Render the `:set xxx` rows that appear inside the Command mode table.
  ## Bool options first, then int/float (value) options — same ordering as
  ## `help_generator.renderSetOptionsSection`.
  for spec in SetOptionTable:
    if spec.kind != sokBool:
      continue
    var syntax = "`set " & spec.longName & "` or `set no" & spec.longName & "`"
    var desc = spec.description
    if spec.shortName.len > 0:
      desc.addStr " (alias: `" & spec.shortName & "`, `no" & spec.shortName & "`)"
    result.add "| " & syntax & " | " & toMarkdownCell(desc) & " |\n"
  for spec in SetOptionTable:
    if spec.kind == sokBool:
      continue
    let syntax = "`set " & spec.longName & "=number`"
    var desc = spec.description
    case spec.kind
    of sokInt:
      desc.addStr "; e.g. `set " & spec.longName & "=" & $spec.intExample & "`"
    of sokFloat:
      desc.addStr "; e.g. `set " & spec.longName & "=" & $spec.floatExample & "`"
    of sokBool:
      discard
    if spec.shortName.len > 0:
      desc.addStr " (alias: `" & spec.shortName & "`)"
    result.add "| " & syntax & " | " & toMarkdownCell(desc) & " |\n"

proc renderCommandModeTable*(): string =
  ## The full Command-mode table: number-jump + shell + head names + set
  ## options + tail names. Special syntax entries (`:N`, `:!cmd`,
  ## `%s/.../.../`, `%d`, `1,10d`) are pulled from `CommandLineSpecialHelp`
  ## so they round-trip with the same wording the TUI help uses.
  result = CommandTableHeader
  result.add renderCommandRow(CommandLineSpecialHelp.lineNumber)
  result.add renderCommandRow(CommandLineSpecialHelp.shellCommand)
  for name in CommandModeHeadNames:
    for e in lookupHelpEntries(name):
      result.add renderCommandRow(e)
  # `%s/.../.../` slots in just before `delete` per howtouse.md ordering,
  # but `CommandModeHeadNames` already emitted `delete`. Emit the
  # substitute/delete-all/delete-range trio after the head block so all
  # `%`-prefixed special syntax stays adjacent.
  result.add renderCommandRow(CommandLineSpecialHelp.substitute)
  result.add renderCommandRow(CommandLineSpecialHelp.deleteAll)
  result.add renderCommandRow(CommandLineSpecialHelp.deleteRange)
  result.add renderSetOptionRows()
  for name in CommandModeTailNames:
    for e in lookupHelpEntries(name):
      result.add renderCommandRow(e)

# Runtime key mapping

proc renderRuntimeKeyMapTable*(): string =
  ## The `:nmap` family. Each spec carries its own `helpEntries`; this
  ## helper just orders them by the canonical name list.
  result = CommandTableHeader
  for name in RuntimeKeyMapNames:
    for e in lookupHelpEntries(name):
      result.add renderCommandRow(e)

# Mode tables (kbd-style)
#
# Thin wrappers over `renderKbdHelpGroup` that pin each mode section in
# `documents/howtouse.md` to the same `HelpGroup` constants
# `help_generator.nim` already uses for the TUI help viewer. Adding a new
# mode is one new wrapper here + one `Sections` entry in
# `tools/gen_howtouse_docs.nim`.

proc renderNormalModeTable*(): string =
  renderKbdHelpGroup(NormalModeCommands)

proc renderVisualModeTable*(): string =
  renderKbdHelpGroup(VisualModeCommands)

proc renderReplaceModeTable*(): string =
  renderKbdHelpGroup(ReplaceModeCommands)

proc renderInsertModeTable*(): string =
  renderKbdHelpGroup(InsertModeCommands)

proc renderBackupModeTable*(): string =
  renderKbdHelpGroup(BackupModeCommands)

proc renderReferencesModeTable*(): string =
  renderKbdHelpGroup(ReferencesModeCommands)

proc renderCallHierarchyModeTable*(): string =
  renderKbdHelpGroup(CallHierarchyModeCommands)

proc renderFilerModeTable*(): string =
  renderKbdHelpGroup(FilerModeCommands)

proc renderFileTreeModeTable*(): string =
  renderKbdHelpGroup(FileTreeModeCommands)

proc renderBufferManagerModeTable*(): string =
  renderKbdHelpGroup(BufferManagerModeCommands)

proc renderBookmarkManagerModeTable*(): string =
  renderKbdHelpGroup(BookmarkManagerModeCommands)

proc renderDocumentSymbolModeTable*(): string =
  renderKbdHelpGroup(DocumentSymbolModeCommands)

proc renderConfigModeTable*(): string =
  renderKbdHelpGroup(ConfigModeCommands)

proc renderLogViewerModeTable*(): string =
  renderKbdHelpGroup(LogViewerModeCommands)

proc renderRecentFileModeTable*(): string =
  renderKbdHelpGroup(RecentFileModeCommands)

proc renderDebugModeTable*(): string =
  renderKbdHelpGroup(DebugModeCommands)

proc renderTerminalInputTable*(): string =
  renderKbdHelpGroup(TerminalInputCommands)

proc renderTerminalNormalTable*(): string =
  renderKbdHelpGroup(TerminalNormalCommands)

proc renderRegisterTable*(): string =
  renderKbdHelpGroup(RegisterCommands)
