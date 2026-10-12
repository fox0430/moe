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

## Built-in language servers and the client-side commands moe runs for them.
## Free of the LSP runtime so the config loader can use them.

type DefaultLspServer* = object
  langId*: string
  command*: string
  args*: seq[string]
  extensions*: seq[string]

const DefaultLspServers* = [
  DefaultLspServer(
    langId: "nim", command: "nimlangserver", extensions: @["nim", "nims", "nimble"]
  ),
  DefaultLspServer(langId: "rust", command: "rust-analyzer", extensions: @["rs"]),
  DefaultLspServer(langId: "python", command: "pylsp", extensions: @["py", "pyw"]),
  DefaultLspServer(
    langId: "typescript",
    command: "typescript-language-server",
    args: @["--stdio"],
    extensions: @["ts", "tsx"],
  ),
  DefaultLspServer(
    langId: "javascript",
    command: "typescript-language-server",
    args: @["--stdio"],
    extensions: @["js", "jsx", "mjs"],
  ),
  DefaultLspServer(
    langId: "lua",
    command: "lua-language-server",
    extensions: @["lua", "luau", "rockspec"],
  ),
  DefaultLspServer(langId: "go", command: "gopls", extensions: @["go"]),
  DefaultLspServer(langId: "c", command: "clangd", extensions: @["c", "h"]),
  DefaultLspServer(
    langId: "cpp",
    command: "clangd",
    extensions: @["cpp", "hpp", "cc", "hh", "cxx", "hxx"],
  ),
]

const
  RunSingleCommand* = "rust-analyzer.runSingle"
  DebugSingleCommand* = "rust-analyzer.debugSingle"
  RunnableCommands* = [RunSingleCommand, DebugSingleCommand]

proc isDefaultLspLanguage*(langId: string): bool =
  ## Whether `langId` has a built-in server.
  for server in DefaultLspServers:
    if server.langId == langId:
      return true
  false
