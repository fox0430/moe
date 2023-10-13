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

import std/[json, unittest, importutils, os, options]
import pkg/results
import moepkg/independentutils
import moepkg/lsp/protocol/enums

import moepkg/lsp/client {.all.}

suite "lsp: Send requests":
  privateAccess(LspClient)

  const
    Command = "nimlsp"
    Trace = TraceValue.verbose

  test "Send initialize":
    var client = initLspClient(Command).get

    const
      Id = 1
      RootPath = ""
    let params = initInitializeParams(RootPath, Trace)

    check client.initialize(Id, params).isOk

  test "Send shutdown":
    var client = initLspClient(Command).get

    const
      Id = 1
      RootPath = ""
    let params = initInitializeParams(RootPath, Trace)
    assert client.initialize(Id, params).isOk
    assert client.initialized.isOk

    check client.shutdown(Id).isOk

  test "Send workspace/didChangeConfiguration":
    var client = initLspClient(Command).get

    const Id = 1
    let
      rootPath = getCurrentDir()
      params = initInitializeParams(rootPath, Trace)
    assert client.initialize(Id, params).isOk
    assert client.initialized.isOk

    check client.workspaceDidChangeConfiguration.isOk

  test "Send textDocument/didOpen":
    var client = initLspClient(Command).get

    const Id = 1
    let
      rootPath = getCurrentDir()
      params = initInitializeParams(rootPath, Trace)
    assert client.initialize(Id, params).isOk
    assert client.initialized.isOk

    const LanguageId = "nim"
    let
      path = getCurrentDir() / "src/moe.nim"
      text = readFile(path)

    check client.textDocumentDidOpen(path, LanguageId, text).isOk

  test "Send textDocument/didChange":
    var client = initLspClient(Command).get

    const Id = 1
    let
      rootPath = getCurrentDir()
      params = initInitializeParams(rootPath, Trace)
    assert client.initialize(Id, params).isOk
    assert client.initialized.isOk

    const LanguageId = "nim"
    let
      path = getCurrentDir() / "src/moe.nim"
      text = readFile(path)
    assert client.textDocumentDidOpen(path, LanguageId, text).isOk

    block:
      const SecondVersion = 2
      let changedText = "echo 1"

      check client.textDocumentDidChange(SecondVersion, path, changedText).isOk

  test "Send textDocument/didClose":
    var client = initLspClient(Command).get

    const Id = 1
    let
      rootPath = getCurrentDir()
      params = initInitializeParams(rootPath, Trace)
    assert client.initialize(Id, params).isOk
    assert client.initialized.isOk

    const LanguageId = "nim"
    let
      path = getCurrentDir() / "src/moe.nim"
      text = readFile(path)
    assert client.textDocumentDidOpen(path, LanguageId, text).isOk

    check client.textDocumentDidClose(path).isOk

  test "Send textDocument/hover":
    var client = initLspClient(Command).get

    const Id = 1
    let
      rootPath = getCurrentDir()
      params = initInitializeParams(rootPath, Trace)
    assert client.initialize(Id, params).isOk
    assert client.initialized.isOk

    const LanguageId = "nim"
    let
      path = getCurrentDir() / "src/moe.nim"
      # Use simple text for the test.
      text = "echo 1"
    assert client.textDocumentDidOpen(path, LanguageId, text).isOk

    let position = BufferPosition(line: 0, column: 0)

    let r = client.textDocumentHover(Id, path, position)
    check r.isOk
    check r.get.contents.get.len > 0

  test "Send textDocument/hover 2":
    var client = initLspClient(Command).get

    const Id = 1
    let
      rootPath = getCurrentDir()
      params = initInitializeParams(rootPath, Trace)
    assert client.initialize(Id, params).isOk
    assert client.initialized.isOk

    const LanguageId = "nim"
    let
      path = getCurrentDir() / "src/moe.nim"
      # Use simple text for the test.
      text = "echo 1"
    assert client.textDocumentDidOpen(path, LanguageId, text).isOk

    block first:
      let position = BufferPosition(line: 0, column: 0)

      let r = client.textDocumentHover(Id, path, position)
      check r.get.contents.get.len > 0

    block second:
      const SecondVersion = 2
      let changedText = "echo 1\necho 2"
      assert client.textDocumentDidChange(SecondVersion, path, changedText).isOk

      let position = BufferPosition(line: 1, column: 0)

      let r = client.textDocumentHover(Id, path, position)
      check r.get.contents.get.len > 0
