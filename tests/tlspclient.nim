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

import std/[unittest, importutils, os, osproc, options]
import pkg/results
import moepkg/independentutils
import moepkg/lsp/protocol/enums
import moepkg/lsp/utils

import utils

import moepkg/lsp/client {.all.}

suite "lsp: Send requests":
  privateAccess(LspClient)

  const
    Command = "nimlangserver"
    Trace = TraceValue.verbose

  var client: LspClient

  setup:
    client = initLspClient(Command).get

  test "Send initialize":
    if not isNimlangserverAvailable():
      skip()
    else:
      const
        Id = 1
        RootPath = ""
      let params = initInitializeParams(RootPath, Trace)

      check client.initialize(Id, params).isOk
      check client.waitingResponse.get == LspMethod.initialize

  test "Send shutdown":
    if not isNimlangserverAvailable():
      skip()
    else:
      const
        Id = 1
        RootPath = ""

      block:
        # Initialize LSP client

        block:
          let params = initInitializeParams(RootPath, Trace)
          assert client.initialize(Id, params).isOk

        const Timeout = 5000
        assert client.readable(Timeout).isOk
        let initializeRes = client.read.get

        block:
          let err = client.initCapacities(initializeRes)
          assert err.isOk

        block:
          # Initialized notification
          let err = client.initialized
          assert err.isOk

      check client.shutdown(Id).isOk

  test "Send workspace/didChangeConfiguration":
    if not isNimlangserverAvailable():
      skip()
    else:
      block:
        # Initialize LSP client

        const Id = 1
        let rootPath = getCurrentDir()

        block:
          let params = initInitializeParams(rootPath, Trace)
          assert client.initialize(Id, params).isOk

        const Timeout = 5000
        assert client.readable(Timeout).isOk
        let initializeRes = client.read.get

        block:
          let err = client.initCapacities(initializeRes)
          assert err.isOk

        block:
          # Initialized notification
          let err = client.initialized
          assert err.isOk

      check client.workspaceDidChangeConfiguration.isOk

  test "Send textDocument/didOpen":
    if not isNimlangserverAvailable():
      skip()
    else:
      const Id = 1

      block:
        # Initialize LSP client

        block:
          let
            rootPath = getCurrentDir()
            params = initInitializeParams(rootPath, Trace)
          assert client.initialize(Id, params).isOk

        const Timeout = 5000
        assert client.readable(Timeout).isOk
        let initializeRes = client.read.get

        block:
          let err = client.initCapacities(initializeRes)
          assert err.isOk

        block:
          # Initialized notification
          let err = client.initialized
          assert err.isOk

        block:
          # workspace/didChangeConfiguration notification
          let err = client.workspaceDidChangeConfiguration
          assert err.isOk

      const LanguageId = "nim"
      let
        path = getCurrentDir() / "src/moe.nim"
        text = readFile(path)

      check client.textDocumentDidOpen(path, LanguageId, text).isOk

  test "Send textDocument/didChange":
    if not isNimlangserverAvailable():
      skip()
    else:
      const
        Id = 1
        LanguageId = "nim"
      let
        path = getCurrentDir() / "src/moe.nim"
        text = readFile(path)

      block:
        # Initialize LSP client

        block:
          let
            rootPath = getCurrentDir()
            params = initInitializeParams(rootPath, Trace)
          assert client.initialize(Id, params).isOk

        const Timeout = 5000
        assert client.readable(Timeout).isOk
        let initializeRes = client.read.get

        block:
          let err = client.initCapacities(initializeRes)
          assert err.isOk

        block:
          # Initialized notification
          let err = client.initialized
          assert err.isOk

        block:
          # workspace/didChangeConfiguration notification
          let err = client.workspaceDidChangeConfiguration
          assert err.isOk

        block:
          # textDocument/diOpen notification
          let err = client.textDocumentDidOpen(path, LanguageId, text)
          assert err.isOk

      block:
        const SecondVersion = 2
        let changedText = "echo 1"

        check client.textDocumentDidChange(SecondVersion, path, changedText).isOk

  test "Send textDocument/didSave":
    if not isNimlangserverAvailable():
      skip()
    else:
      const
        Id = 1
        LanguageId = "nim"
      let
        path = getCurrentDir() / "src/moe.nim"
        text = readFile(path)

      block:
        # Initialize LSP client

        block:
          let
            rootPath = getCurrentDir()
            params = initInitializeParams(rootPath, Trace)
          assert client.initialize(Id, params).isOk

        const Timeout = 5000
        assert client.readable(Timeout).isOk
        let initializeRes = client.read.get

        block:
          let err = client.initCapacities(initializeRes)
          assert err.isOk

        block:
          # Initialized notification
          let err = client.initialized
          assert err.isOk

        block:
          # workspace/didChangeConfiguration notification
          let err = client.workspaceDidChangeConfiguration
          assert err.isOk

        block:
          # textDocument/diOpen notification
          let err = client.textDocumentDidOpen(path, LanguageId, text)
          assert err.isOk

      block:
        const Version = 1
        check client.textDocumentDidSave(Version, path, text).isOk

  test "Send textDocument/didClose":
    if not isNimlangserverAvailable():
      skip()
    else:
      const
        Id = 1
        LanguageId = "nim"
      let
        path = getCurrentDir() / "src/moe.nim"
        text = readFile(path)

      block:
        # Initialize LSP client

        block:
          let
            rootPath = getCurrentDir()
            params = initInitializeParams(rootPath, Trace)
          assert client.initialize(Id, params).isOk

        const Timeout = 5000
        assert client.readable(Timeout).isOk
        let initializeRes = client.read.get

        block:
          let err = client.initCapacities(initializeRes)
          assert err.isOk

        block:
          # Initialized notification
          let err = client.initialized
          assert err.isOk

        block:
          # workspace/didChangeConfiguration notification
          let err = client.workspaceDidChangeConfiguration
          assert err.isOk

        block:
          # textDocument/diOpen notification
          let err = client.textDocumentDidOpen(path, LanguageId, text)
          assert err.isOk

      check client.textDocumentDidClose(path).isOk

  test "Send textDocument/hover":
    if not isNimlangserverAvailable():
      skip()
    else:
      let rootPath = getCurrentDir()

      const
        Id = 1
        LanguageId = "nim"
        Text = "echo 1" # Use simple text for the test.

      let
        path = getCurrentDir() / "src/moe.nim"

      block:
        # Initialize LSP client

        block:
          let params = initInitializeParams(rootPath, Trace)
          assert client.initialize(Id, params).isOk

        const Timeout = 5000
        assert client.readable(Timeout).isOk
        let initializeRes = client.read.get

        block:
          let err = client.initCapacities(initializeRes)
          assert err.isOk

        block:
          # Initialized notification
          let err = client.initialized
          assert err.isOk

        block:
          # workspace/didChangeConfiguration notification
          let err = client.workspaceDidChangeConfiguration
          assert err.isOk

        block:
          # textDocument/diOpen notification
          let err = client.textDocumentDidOpen(path, LanguageId, Text)
          assert err.isOk

      let position = BufferPosition(line: 0, column: 0)

      check client.textDocumentHover(Id, path, position).isOk
      check client.waitingResponse.get == LspMethod.textDocumentHover

  test "Send textDocument/completion":
    if not isNimlangserverAvailable():
      skip()
    else:
      let rootPath = getCurrentDir()

      const
        Id = 1
        LanguageId = "nim"
        Text = "echo 1\n" # Use simple text for the test.

      let
        path = getCurrentDir() / "src/moe.nim"

      block:
        # Initialize LSP client

        block:
          let params = initInitializeParams(rootPath, Trace)
          assert client.initialize(Id, params).isOk

        const Timeout = 5000
        assert client.readable(Timeout).isOk
        let initializeRes = client.read.get

        block:
          let err = client.initCapacities(initializeRes)
          assert err.isOk

        block:
          # Initialized notification
          let err = client.initialized
          assert err.isOk

        block:
          # workspace/didChangeConfiguration notification
          let err = client.workspaceDidChangeConfiguration
          assert err.isOk

        block:
          # textDocument/diOpen notification
          let err = client.textDocumentDidOpen(path, LanguageId, Text)
          assert err.isOk

      block:
        const SecondVersion = 2
        let changedText = "echo 1\ne"
        check client.textDocumentDidChange(SecondVersion, path, changedText).isOk

      let position = BufferPosition(line: 1, column: 0)
      const IsIncompleteTrigger = false
      check client.textDocumentCompletion(
        Id,
        path,
        position,
        IsIncompleteTrigger,
        "e").isOk
      check client.waitingResponse.get == LspMethod.textDocumentCompletion
