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

## Public types for the KeyRouter dispatcher.
##
## KeyRouter owns runtime-mapping dispatch decisions. Built-in command
## resolution (sequence / single binding / numeric prefix / `f t r` operand
## waits) is wrapped by `resolveBuiltin` (key_router.nim), which maps
## `KeyBindingRegistry.processKey` onto the `rrCommand` variant carrying the
## resolved `Command`. `Command` is intentionally *not* re-exported (only
## `options` is) so the `editor_types` `except Command` guard keeps working
## through `import key_router`.

import std/options

import ../key_bindings

# Re-export support libs only; deliberately *not* re-exporting `Command` or
# other `key_bindings` types so callers must import them explicitly and the
# editor_types `except Command` guard keeps working through `import key_router`.
export options

type
  TimeoutPolicy* = object
    timeoutlen*: int ## Milliseconds; mirror of config.standard.timeoutlen
    enabled*: bool

  RouteResultKind* = enum
    rrExecuteRuntimeCommand
      ## Runtime mapping with `rmkCommand` fired. Caller executes the named
      ## command (typically via `executeCommandDirect`).
    rrExecuteRuntimeKeySequence
      ## Runtime mapping with `rmkKeySequence` fired. Caller replays the
      ## target keys (typically via `playbackMacro`).
    rrWaiting
      ## Accumulation continues. `waitsForTimeout` is true for runtime-mapping
      ## prefixes (timer should be armed); built-in sequence prefixes never
      ## time out (Vim spec).
    rrCancelled ## Escape consumed pending state.
    rrUnhandled
      ## From `feedKey`: the router has nothing to say about this key; the
      ## caller should proceed with normal (built-in) processing. From
      ## `resolveBuiltin`: the key may already have been *consumed* as an
      ## invalid-sequence terminator — see that proc's note; do not blindly
      ## re-process `key`.
    rrUnhandledBatch
      ## Accumulator was flushed without a match. Caller replays these keys
      ## one by one with `isReplayingMapping = true`.
    rrCommand
      ## A built-in binding/sequence was resolved. `command` carries the
      ## resolved `Command`; the caller executes it (Normal-mode dispatcher).

  RouteResult* = object
    case kind*: RouteResultKind
    of rrExecuteRuntimeCommand:
      commandName*: string
    of rrExecuteRuntimeKeySequence:
      targetKeys*: seq[string]
      noremap*: bool
        ## When false the replayed keys are re-expanded through the mapping
        ## table (`:map`); when true they are replayed verbatim (`:noremap`).
    of rrWaiting:
      waitsForTimeout*: bool
    of rrUnhandled:
      key*: KeyCombo
    of rrUnhandledBatch:
      keys*: seq[KeyCombo]
    of rrCancelled:
      discard
    of rrCommand:
      command*: Command
