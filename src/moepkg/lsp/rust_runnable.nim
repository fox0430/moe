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

## Convert a rust-analyzer `Runnable` (the argument of the client-side
## `rust-analyzer.runSingle` / `rust-analyzer.debugSingle` CodeLens commands)
## into a shell command string that moe runs in its embedded terminal.
##
## rust-analyzer never executes these itself: it expects the client to take the
## Runnable's cargo arguments and spawn the build/test process. For `debug` we
## reuse the same cargo invocation but override cargo's test-binary runner with
## `rust-gdb --args`, so the produced binary is launched under the debugger
## without needing to resolve the artifact path ourselves.

import std/[json, os, strutils]

import pkg/results

const RustGdbRunnerConfig = "target.\"cfg(all())\".runner=[\"rust-gdb\",\"--args\"]"

proc jsonStrSeq(n: JsonNode): seq[string] =
  ## Collect a JSON string array into a seq[string] (empty if nil/not an array).
  if n != nil and n.kind == JArray:
    for item in n:
      result.add item.getStr

proc buildRunnableCommand*(runnable: JsonNode, debug: bool): Result[string, string] =
  ## Build the shell command for a cargo Runnable.
  ##
  ## run:   cd <root> && cargo <cargoArgs> <cargoExtraArgs> -- <executableArgs>
  ## debug: cd <root> && cargo <cargoArgs> --config <rust-gdb runner>
  ##                          <cargoExtraArgs> -- <executableArgs>
  ##
  ## Every token is passed through quoteShell so test names and paths with
  ## shell-special characters cannot break out of the command.
  if runnable.kind != JObject or not runnable.hasKey("args"):
    return err("Runnable has no args")

  let args = runnable["args"]
  if args.kind != JObject:
    return err("Runnable args is not an object")

  let cargoArgs = jsonStrSeq(args.getOrDefault("cargoArgs"))
  if cargoArgs.len == 0:
    return err("Runnable has no cargoArgs")
  let cargoExtraArgs = jsonStrSeq(args.getOrDefault("cargoExtraArgs"))
  let executableArgs = jsonStrSeq(args.getOrDefault("executableArgs"))
  let workspaceRoot = args.getOrDefault("workspaceRoot").getStr("")

  var tokens = @["cargo"]
  tokens.add cargoArgs
  if debug:
    tokens.add "--config"
    tokens.add RustGdbRunnerConfig
  tokens.add cargoExtraArgs
  if executableArgs.len > 0:
    tokens.add "--"
    tokens.add executableArgs

  var quoted: seq[string]
  for t in tokens:
    quoted.add quoteShell(t)
  var command = quoted.join(" ")

  if workspaceRoot.len > 0:
    command = "cd " & quoteShell(workspaceRoot) & " && " & command

  ok(command)
