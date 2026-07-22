## Regenerate the auto-generated portions of `documents/howtouse.md`.
##
## Usage: `nim r tools/gen_howtouse_docs.nim` (or `nimble genhowtouse`).
##
## Each `<!-- AUTO-GEN:start Xxx --> ... <!-- AUTO-GEN:end Xxx -->` block in
## the markdown file is replaced with a freshly generated table. The body
## comes from `src/moepkg/help_markdown.nim`, which renders the same
## `HelpEntry` / `HelpGroup` data that `help_generator.nim` consumes for the
## TUI help viewer. Sections outside the marker pairs (mode `<details>`
## wrappers, sub-section headers, narrative paragraphs) are left untouched.
##
## Phase 1 added `Exiting`, `CommandMode`, and `RuntimeKeyMap`. Phase 2
## extended the dispatch table to every mode-specific key table (Normal,
## Register, Visual, Replace, Insert, Backupmanager, References, Call
## Hierarchy, Filer, Terminal-Input, Terminal-Normal) by reusing the same
## `HelpGroup` constants `help_generator.nim` feeds into the TUI help
## viewer. Phase 3 added the remaining viewer/manager modes (FileTree,
## BufferManager, BookmarkManager, DocumentSymbol, Configuration,
## LogViewer, RecentFile, Debug).

import std/[os, strutils]

import ../src/moepkg/help_markdown

const DocsPath* = currentSourcePath().parentDir.parentDir / "documents" / "howtouse.md"
  ## Anchored to this source file so the tool works regardless of the
  ## process working directory — `nimble genhowtouse` happens to run from
  ## the project root, but `nim r tools/gen_howtouse_docs.nim` from a
  ## subdirectory must resolve the same file.

# Section dispatch.
#
# The list is split into "name + body builder" tuples; adding a section is one
# new entry. The same pattern is used by `tools/gen_config_docs.nim` but with
# a macro — here a plain seq is enough because every body builder has the
# same `proc(): string` signature.
#
# `let` (not `const`) so the `body` field accepts closures as well as plain
# top-level procs without forcing a `{.nimcall.}` pragma on every renderer.
# This binary is a one-shot tool, so the once-per-run construction is free.
let Sections: seq[tuple[name: string, body: proc(): string]] = @[
  (name: "Exiting", body: renderExitingTable),
  (name: "NormalMode", body: renderNormalModeTable),
  (name: "Register", body: renderRegisterTable),
  (name: "VisualMode", body: renderVisualModeTable),
  (name: "ReplaceMode", body: renderReplaceModeTable),
  (name: "InsertMode", body: renderInsertModeTable),
  (name: "BackupManagerMode", body: renderBackupModeTable),
  (name: "ReferencesMode", body: renderReferencesModeTable),
  (name: "CallHierarchyMode", body: renderCallHierarchyModeTable),
  (name: "FilerMode", body: renderFilerModeTable),
  (name: "FileTreeMode", body: renderFileTreeModeTable),
  (name: "BufferManagerMode", body: renderBufferManagerModeTable),
  (name: "BookmarkManagerMode", body: renderBookmarkManagerModeTable),
  (name: "DocumentSymbolMode", body: renderDocumentSymbolModeTable),
  (name: "ConfigMode", body: renderConfigModeTable),
  (name: "LogViewerMode", body: renderLogViewerModeTable),
  (name: "RecentFileMode", body: renderRecentFileModeTable),
  (name: "DebugMode", body: renderDebugModeTable),
  (name: "TerminalInput", body: renderTerminalInputTable),
  (name: "TerminalNormal", body: renderTerminalNormalTable),
  (name: "CommandMode", body: renderCommandModeTable),
  (name: "RuntimeKeyMap", body: renderRuntimeKeyMapTable),
]

proc replaceMarkers(text: string, name, body: string): string =
  ## Replace the content between `<!-- AUTO-GEN:start name -->` and
  ## `<!-- AUTO-GEN:end name -->` with the new `body`. Raises if either
  ## marker is missing, if any marker name appears more than once, or if
  ## the start/end pair is interleaved with another section's markers
  ## (which would silently swallow or duplicate content on regeneration).
  ## Mirrors the helper of the same name in `tools/gen_config_docs.nim`.
  let startMarker = "<!-- AUTO-GEN:start " & name & " -->"
  let endMarker = "<!-- AUTO-GEN:end " & name & " -->"
  let startIdx = text.find(startMarker)
  if startIdx < 0:
    raise newException(ValueError, "missing start marker for " & name)
  if text.find(startMarker, startIdx + startMarker.len) >= 0:
    raise
      newException(ValueError, "duplicate <!-- AUTO-GEN:start " & name & " --> marker")
  let endIdx = text.find(endMarker, startIdx + startMarker.len)
  if endIdx < 0:
    raise newException(ValueError, "missing end marker for " & name)
  if text.find(endMarker, endIdx + endMarker.len) >= 0:
    raise
      newException(ValueError, "duplicate <!-- AUTO-GEN:end " & name & " --> marker")
  # Crossing check: no other AUTO-GEN start/end may sit between our start
  # and end. A mistyped `<!-- AUTO-GEN:start CommanMode -->` inside the
  # Exiting block, or a swapped `end Exiting` / `end CommandMode` pair,
  # would otherwise mangle the replacement range. We only need to look at
  # `<!-- AUTO-GEN:` since both start- and end-markers share that prefix.
  let inner = text[startIdx + startMarker.len ..< endIdx]
  let strayIdx = inner.find("<!-- AUTO-GEN:")
  if strayIdx >= 0:
    let strayEol = inner.find('\n', strayIdx)
    let strayLen =
      if strayEol < 0:
        inner.len - strayIdx
      else:
        strayEol - strayIdx
    raise newException(
      ValueError,
      "section " & name & " contains a stray AUTO-GEN marker: " &
        inner[strayIdx ..< strayIdx + strayLen] &
        " (mismatched start/end pair or nested block?)",
    )
  let before = text[0 ..< startIdx + startMarker.len]
  let after = text[endIdx ..^ 1]
  before & "\n" & body & after

proc regenerateHowtouseDocs*(input: string): string =
  ## Apply every section's AUTO-GEN replacement to `input` and return the
  ## new markdown content. Pure function — does not touch the filesystem.
  ## Used both by the CLI runner (read → regenerate → write) and by the
  ## sync test (read → regenerate → compare), so they share one code path.
  result = input
  for (name, body) in Sections:
    result = replaceMarkers(result, name, body())

proc main() =
  if not fileExists(DocsPath):
    echo "missing: ", DocsPath
    quit 1

  let original = readFile(DocsPath)
  let regenerated = regenerateHowtouseDocs(original)
  if regenerated != original:
    writeFile(DocsPath, regenerated)
    echo "regenerated ", Sections.len, " section(s) in ", DocsPath
  else:
    echo "up-to-date: ", DocsPath, " (", Sections.len, " section(s) checked)"

when isMainModule:
  main()
