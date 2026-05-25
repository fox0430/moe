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

## Tests for editor_signaturehelp.nim

import std/unittest

import ../src/moepkg/[editor, config, config_loader]
import ../src/moepkg/editor_signaturehelp

proc createTestEditor(): Editor =
  let config = newEditorConfig()
  let vr = newValidationResult()
  result = newEditor(config, vr)

proc createTestEditorWithLspDisabled(): Editor =
  let config = newEditorConfig()
  let vr = newValidationResult()
  result = newEditor(config, vr)
  result.lsp.enabled = false

suite "editor_signaturehelp - requestSignatureHelpFromLsp":
  test "Does nothing when LSP is disabled":
    let e = createTestEditorWithLspDisabled()
    e.state.mode = EditorMode.Insert

    e.requestSignatureHelpFromLsp()

    check e.state.lspCache.pendingSignatureHelpRequestId == 0

  test "Does nothing when not in Insert mode":
    let e = createTestEditor()
    e.lsp.enabled = true
    e.state.mode = EditorMode.Normal

    e.requestSignatureHelpFromLsp()

    check e.state.lspCache.pendingSignatureHelpRequestId == 0
