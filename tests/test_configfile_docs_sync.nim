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

## Verify that `documents/configfile.md` is in sync with the auto-gen
## output produced by `tools/gen_config_docs.nim`. Calls the generator
## in-process (no subprocess, no file mutation) and compares the result
## with the checked-in file; any diff means a config field was added or
## modified without running `nimble gendocs`.

import std/[unittest, algorithm, strutils]

import ../tools/gen_config_docs
import ../src/moepkg/config_loader/lsp {.all.}

suite "configfile.md auto-gen sync":
  test "regenerating produces no diff":
    let original = readFile(DocsPath)
    var regenerated = ""
    var regenOk = false
    try:
      regenerated = regenerateConfigDocs(original)
      regenOk = true
    except CatchableError as e:
      # Most common cause: someone hand-edited configfile.md and removed
      # or typo'd one of the `<!-- AUTO-GEN:start … -->` / `:end` markers.
      # Surface a readable hint instead of a bare traceback.
      echo "documents/configfile.md has malformed AUTO-GEN markers:"
      echo "  ", e.msg
      echo "Restore the marker pair, then run `nimble gendocs` to regenerate."

    check regenOk
    if regenOk:
      if original != regenerated:
        echo "documents/configfile.md is out of sync with config.nim."
        echo "Run `nimble gendocs` and commit the result."
      check original == regenerated

suite "configfile.md hand-written [Lsp.{languageId}] table":
  ## The dynamic language-server table has no `{.cfgSection.}` type to derive
  ## from, so it sits between two AUTO-GEN regions unprotected. Pin at least
  ## its key list against the loader.
  test "documents exactly the keys the loader accepts":
    let doc = readFile(DocsPath)
    let startIdx = doc.find("### Lsp.{languageId} table")
    check startIdx >= 0

    let rest = doc[startIdx ..^ 1]
    let endIdx = rest.find("\n### ")
    let blockText =
      if endIdx >= 0:
        rest[0 ..< endIdx]
      else:
        rest

    var documented: seq[string]
    for line in blockText.splitLines:
      if line.startsWith("| ") and not line.startsWith("| Name |"):
        documented.add line.split('|')[1].strip

    check documented.sorted == @LspServerConfigKeys.sorted
