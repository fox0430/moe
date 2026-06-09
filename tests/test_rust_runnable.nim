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

import std/[unittest, json]

import pkg/results

import ../src/moepkg/lsp/rust_runnable

proc testRunnable(
    cargoArgs: seq[string],
    executableArgs: seq[string] = @[],
    cargoExtraArgs: seq[string] = @[],
    workspaceRoot = "/home/user/proj",
): JsonNode =
  ## Build a minimal rust-analyzer Runnable JSON for tests.
  %*{
    "label": "test",
    "kind": "cargo",
    "args": {
      "workspaceRoot": workspaceRoot,
      "cargoArgs": cargoArgs,
      "cargoExtraArgs": cargoExtraArgs,
      "executableArgs": executableArgs,
    },
  }

suite "rust_runnable: buildRunnableCommand":
  test "run with executable args":
    let r = testRunnable(
      cargoArgs = @["test", "--package", "foo", "--lib"],
      executableArgs = @["mymod::my_test", "--exact", "--nocapture"],
    )
    let res = buildRunnableCommand(r, debug = false)
    check res.isOk
    check res.get ==
      "cd /home/user/proj && cargo test --package foo --lib -- " &
      "mymod::my_test --exact --nocapture"

  test "run without executable args omits trailing --":
    let r = testRunnable(cargoArgs = @["test", "--package", "foo"])
    let res = buildRunnableCommand(r, debug = false)
    check res.isOk
    check res.get == "cd /home/user/proj && cargo test --package foo"

  test "debug injects rust-gdb runner via --config":
    let r = testRunnable(
      cargoArgs = @["test", "--package", "foo", "--lib"],
      executableArgs = @["mymod::my_test", "--exact"],
    )
    let res = buildRunnableCommand(r, debug = true)
    check res.isOk
    check res.get ==
      "cd /home/user/proj && cargo test --package foo --lib " &
      "--config 'target.\"cfg(all())\".runner=[\"rust-gdb\",\"--args\"]' " &
      "-- mymod::my_test --exact"

  test "cargoExtraArgs are appended before --":
    let r = testRunnable(
      cargoArgs = @["test"],
      cargoExtraArgs = @["--release"],
      executableArgs = @["my_test"],
    )
    let res = buildRunnableCommand(r, debug = false)
    check res.isOk
    check res.get == "cd /home/user/proj && cargo test --release -- my_test"

  test "empty workspaceRoot drops the cd prefix":
    let r = testRunnable(cargoArgs = @["test"], workspaceRoot = "")
    let res = buildRunnableCommand(r, debug = false)
    check res.isOk
    check res.get == "cargo test"

  test "workspaceRoot with spaces is quoted":
    let r = testRunnable(cargoArgs = @["test"], workspaceRoot = "/home/my proj")
    let res = buildRunnableCommand(r, debug = false)
    check res.isOk
    check res.get == "cd '/home/my proj' && cargo test"

  test "test name with shell metacharacters is quoted":
    let r =
      testRunnable(cargoArgs = @["test"], executableArgs = @["mod::test $(rm -rf /)"])
    let res = buildRunnableCommand(r, debug = false)
    check res.isOk
    check res.get == "cd /home/user/proj && cargo test -- 'mod::test $(rm -rf /)'"

  test "missing args object is an error":
    let res = buildRunnableCommand(%*{"label": "x"}, debug = false)
    check res.isErr

  test "missing cargoArgs is an error":
    let r = %*{"label": "x", "args": {"workspaceRoot": "/p"}}
    let res = buildRunnableCommand(r, debug = false)
    check res.isErr
