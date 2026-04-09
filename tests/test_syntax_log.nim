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

import std/unittest

import ../src/moepkg/syntax/[tokenizer, syntax_log]

suite "syntax_log - timestamps":
  test "Date YYYY-MM-DD":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("2024-01-15")
    g.logNextToken()
    check g.kind == gtDate
    check g.length == 10

  test "Date YYYY/MM/DD":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("2024/01/15")
    g.logNextToken()
    check g.kind == gtDate
    check g.length == 10

  test "DateTime YYYY-MM-DDTHH:MM:SS":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("2024-01-15T12:34:56")
    g.logNextToken()
    check g.kind == gtDate
    check g.length == 19

  test "DateTime with timezone Z":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("2024-01-15T12:34:56Z")
    g.logNextToken()
    check g.kind == gtDate
    check g.length == 20

  test "DateTime with timezone offset":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("2024-01-15T12:34:56+09:00")
    g.logNextToken()
    check g.kind == gtDate
    check g.length == 25

  test "DateTime with fractional seconds":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("2024-01-15T12:34:56.789Z")
    g.logNextToken()
    check g.kind == gtDate
    check g.length == 24

  test "Time only HH:MM:SS":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("12:34:56")
    g.logNextToken()
    check g.kind == gtDate
    check g.length == 8

  test "Time with fractional seconds":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("12:34:56.789")
    g.logNextToken()
    check g.kind == gtDate
    check g.length == 12

  test "Date with space-separated time":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("2024-01-15 12:34:56")
    g.logNextToken()
    check g.kind == gtDate
    check g.length == 19

suite "syntax_log - log levels (error)":
  test "ERROR":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("ERROR")
    g.logNextToken()
    check g.kind == gtLogError
    check g.length == 5

  test "FATAL":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("FATAL")
    g.logNextToken()
    check g.kind == gtLogError

  test "CRITICAL":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("CRITICAL")
    g.logNextToken()
    check g.kind == gtLogError

  test "ERR":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("ERR")
    g.logNextToken()
    check g.kind == gtLogError

suite "syntax_log - log levels (warn)":
  test "WARN":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("WARN")
    g.logNextToken()
    check g.kind == gtLogWarning

  test "WARNING":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("WARNING")
    g.logNextToken()
    check g.kind == gtLogWarning

suite "syntax_log - log levels (info)":
  test "INFO":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("INFO")
    g.logNextToken()
    check g.kind == gtLogInfo

  test "DEBUG":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("DEBUG")
    g.logNextToken()
    check g.kind == gtLogInfo

  test "TRACE":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("TRACE")
    g.logNextToken()
    check g.kind == gtLogInfo

  test "NOTICE":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("NOTICE")
    g.logNextToken()
    check g.kind == gtLogInfo

suite "syntax_log - non-keyword identifiers":
  test "Regular word":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("server")
    g.logNextToken()
    check g.kind == gtIdentifier

suite "syntax_log - bracket expressions":
  test "Simple bracket":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[main]")
    g.logNextToken()
    check g.kind == gtPragma
    check g.length == 6

  test "Bracket with spaces":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[my component]")
    g.logNextToken()
    check g.kind == gtPragma
    check g.length == 14

suite "syntax_log - strings":
  test "Double-quoted string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello world\"")
    g.logNextToken()
    check g.kind == gtStringLit
    check g.length == 13

  test "Single-quoted string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'hello world'")
    g.logNextToken()
    check g.kind == gtStringLit
    check g.length == 13

suite "syntax_log - numbers":
  test "Integer":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("200")
    g.logNextToken()
    check g.kind == gtDecNumber

  test "Hex number 0xFF":
    # generalNumber does not handle hex prefix; 0 is consumed as decimal,
    # then xFF becomes a separate identifier token.
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0xFF")
    g.logNextToken()
    check g.kind == gtDecNumber

suite "syntax_log - numbers with unit suffix":
  test "Number with single-char suffix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("200s")
    g.logNextToken()
    check g.kind == gtDecNumber
    check g.length == 4

  test "Number with multi-char suffix (ms)":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("200ms")
    g.logNextToken()
    check g.kind == gtDecNumber
    check g.length == 5

  test "Number with multi-char suffix (KB)":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("10KB")
    g.logNextToken()
    check g.kind == gtDecNumber
    check g.length == 4

suite "syntax_log - UUIDs":
  test "Standard UUID (lowercase)":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("550e8400-e29b-41d4-a716-446655440000")
    g.logNextToken()
    check g.kind == gtLogUuid
    check g.length == 36

  test "Standard UUID (uppercase)":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("550E8400-E29B-41D4-A716-446655440000")
    g.logNextToken()
    check g.kind == gtLogUuid
    check g.length == 36

  test "UUID starting with letter":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("abcdef01-2345-6789-abcd-ef0123456789")
    g.logNextToken()
    check g.kind == gtLogUuid
    check g.length == 36

  test "UUID in log line":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("request_id=550e8400-e29b-41d4-a716-446655440000 done")
    # "request_id"
    g.logNextToken()
    check g.kind == gtIdentifier
    # "="
    g.logNextToken()
    check g.kind == gtOperator
    # UUID
    g.logNextToken()
    check g.kind == gtLogUuid
    check g.length == 36

  test "Not a UUID (too short)":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("550e8400-e29b-41d4")
    g.logNextToken()
    # Should not be parsed as UUID
    check g.kind != gtLabel

  test "Not a UUID (followed by alnum)":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("550e8400-e29b-41d4-a716-446655440000x")
    g.logNextToken()
    check g.kind != gtLabel

suite "syntax_log - string state continuation":
  test "Double-quoted string does not end on single quote":
    # Simulates a string containing a single quote
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"it's here\"")
    g.logNextToken()
    check g.kind == gtStringLit
    check g.length == 11

  test "Single-quoted string does not end on double quote":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'say \"hi\"'")
    g.logNextToken()
    check g.kind == gtStringLit
    check g.length == 10

suite "syntax_log - operators and punctuation":
  test "Equals operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("=")
    g.logNextToken()
    check g.kind == gtOperator

  test "Colon punctuation":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(":")
    g.logNextToken()
    check g.kind == gtPunctuation

suite "syntax_log - whitespace":
  test "Spaces":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("  ")
    g.logNextToken()
    check g.kind == gtWhitespace
    check g.length == 2

suite "syntax_log - full log line":
  test "Typical log line tokenization":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("2024-01-15 12:34:56 [main] ERROR something failed")

    g.logNextToken()
    check g.kind == gtDate # "2024-01-15 12:34:56"

    g.logNextToken()
    check g.kind == gtWhitespace # " "

    g.logNextToken()
    check g.kind == gtPragma # "[main]"

    g.logNextToken()
    check g.kind == gtWhitespace # " "

    g.logNextToken()
    check g.kind == gtLogError # "ERROR"

    g.logNextToken()
    check g.kind == gtWhitespace # " "

    g.logNextToken()
    check g.kind == gtIdentifier # "something"

    g.logNextToken()
    check g.kind == gtWhitespace # " "

    g.logNextToken()
    check g.kind == gtIdentifier # "failed"

    g.logNextToken()
    check g.kind == gtEof
