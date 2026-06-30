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

import std/[unittest, options, strutils]

import ../src/moepkg/uri_utils

suite "findAllUris":
  test "No URIs":
    let result = findAllUris("just plain text")
    check result.len == 0

  test "Empty string":
    let result = findAllUris("")
    check result.len == 0

  test "Single http URL":
    let result = findAllUris("Visit http://example.com for info")
    check result.len == 1
    check result[0].uri == "http://example.com"
    check result[0].start == 6
    check result[0].finish == 23

  test "Single https URL":
    let result = findAllUris("Visit https://example.com/path?q=1 for info")
    check result.len == 1
    check result[0].uri == "https://example.com/path?q=1"

  test "Multiple URIs on one line":
    let result = findAllUris("http://a.com and https://b.com")
    check result.len == 2
    check result[0].uri == "http://a.com"
    check result[1].uri == "https://b.com"

  test "file:// URI":
    let result = findAllUris("open file:///home/user/test.txt here")
    check result.len == 1
    check result[0].uri == "file:///home/user/test.txt"

  test "mailto: URI":
    let result = findAllUris("email mailto:user@example.com please")
    check result.len == 1
    check result[0].uri == "mailto:user@example.com"

  test "ftp:// URI":
    let result = findAllUris("download ftp://files.example.com/pub")
    check result.len == 1
    check result[0].uri == "ftp://files.example.com/pub"

  test "ssh:// URI":
    let result = findAllUris("connect ssh://git@github.com/repo")
    check result.len == 1
    check result[0].uri == "ssh://git@github.com/repo"

  test "Strip trailing period":
    let result = findAllUris("See https://example.com.")
    check result.len == 1
    check result[0].uri == "https://example.com"

  test "Strip trailing comma":
    let result = findAllUris("https://a.com, https://b.com")
    check result.len == 2
    check result[0].uri == "https://a.com"
    check result[1].uri == "https://b.com"

  test "Strip trailing semicolon":
    let result = findAllUris("https://example.com;")
    check result.len == 1
    check result[0].uri == "https://example.com"

  test "Strip trailing exclamation mark":
    let result = findAllUris("Check https://example.com!")
    check result.len == 1
    check result[0].uri == "https://example.com"

  test "Strip trailing question mark":
    let result = findAllUris("Is it https://example.com?")
    check result.len == 1
    check result[0].uri == "https://example.com"

  test "Strip multiple trailing punctuation":
    let result = findAllUris("https://example.com...")
    check result.len == 1
    check result[0].uri == "https://example.com"

  test "Balanced parentheses (Wikipedia)":
    let result = findAllUris("https://en.wikipedia.org/wiki/Foo_(bar)")
    check result.len == 1
    check result[0].uri == "https://en.wikipedia.org/wiki/Foo_(bar)"

  test "Unbalanced trailing parenthesis":
    let result = findAllUris("(https://example.com)")
    check result.len == 1
    check result[0].uri == "https://example.com"

  test "URL at end of line":
    let result = findAllUris("go to https://example.com")
    check result.len == 1
    check result[0].uri == "https://example.com"

  test "URL at start of line":
    let result = findAllUris("https://example.com is the site")
    check result.len == 1
    check result[0].uri == "https://example.com"

  test "URL is the entire line":
    let result = findAllUris("https://example.com/path")
    check result.len == 1
    check result[0].uri == "https://example.com/path"
    check result[0].start == 0
    check result[0].finish == 23

  test "Case insensitive scheme":
    let result = findAllUris("HTTPS://EXAMPLE.COM/PATH")
    check result.len == 1
    check result[0].uri == "HTTPS://EXAMPLE.COM/PATH"

  test "URL with port number":
    let result = findAllUris("http://localhost:8080/api/v1")
    check result.len == 1
    check result[0].uri == "http://localhost:8080/api/v1"

  test "URL with fragment":
    let result = findAllUris("https://example.com/page#section")
    check result.len == 1
    check result[0].uri == "https://example.com/page#section"

  test "URL with multiple query parameters":
    let result = findAllUris("https://example.com/search?q=test&lang=en")
    check result.len == 1
    check result[0].uri == "https://example.com/search?q=test&lang=en"

  test "URL inside angle brackets":
    let result = findAllUris("See <https://example.com> for details")
    check result.len == 1
    check result[0].uri == "https://example.com"

  test "URL inside double quotes":
    let result = findAllUris("""link "https://example.com" here""")
    check result.len == 1
    check result[0].uri == "https://example.com"

  test "Scheme only, no body":
    let result = findAllUris("http:// next word")
    check result.len == 0

  test "URL after multibyte characters":
    # "日本語 " is 4 runes, URL starts at rune 4
    let result = findAllUris("日本語 https://example.com here")
    check result.len == 1
    check result[0].uri == "https://example.com"
    check result[0].start == 4
    check result[0].finish == 22

  test "URL between multibyte characters":
    let result = findAllUris("見て https://example.com テスト")
    check result.len == 1
    check result[0].uri == "https://example.com"
    check result[0].start == 3
    check result[0].finish == 21

  test "maxRunes bounds the scan past the cap":
    # A URI that starts past the cap is not reported (it would not be
    # highlighted, and scanning the whole long line every edit is the cost the
    # cap avoids).
    let line = "x".repeat(40) & " https://example.com"
    check findAllUris(line).len == 1 # uncapped: found
    check findAllUris(line, 20).len == 0 # capped at 20 runes: skipped

  test "maxRunes = 0 disables the cap":
    let line = "x".repeat(40) & " https://example.com"
    check findAllUris(line, 0).len == 1

  test "maxRunes keeps a URI fully within the cap":
    let result = findAllUris("https://example.com " & "x".repeat(5000), 100)
    check result.len == 1
    check result[0].uri == "https://example.com"
  test "Cursor at start of URI":
    let result = extractUriAtPosition("Visit https://example.com here", 6)
    check result.isSome
    check result.get == "https://example.com"

  test "Cursor in middle of URI":
    let result = extractUriAtPosition("Visit https://example.com here", 15)
    check result.isSome
    check result.get == "https://example.com"

  test "Cursor at end of URI":
    let result = extractUriAtPosition("Visit https://example.com here", 24)
    check result.isSome
    check result.get == "https://example.com"

  test "Cursor before URI":
    let result = extractUriAtPosition("Visit https://example.com here", 3)
    check result.isNone

  test "Cursor after URI":
    let result = extractUriAtPosition("Visit https://example.com here", 26)
    check result.isNone

  test "Cursor at finish + 1 boundary":
    # "https://example.com" finishes at 24, cursor at 25 (space) should miss
    let result = extractUriAtPosition("Visit https://example.com here", 25)
    check result.isNone

  test "Cursor on second URI":
    let line = "http://a.com and https://b.com end"
    let result = extractUriAtPosition(line, 20)
    check result.isSome
    check result.get == "https://b.com"

  test "No URI on line":
    let result = extractUriAtPosition("just some text", 5)
    check result.isNone

  test "Empty line":
    let result = extractUriAtPosition("", 0)
    check result.isNone

  test "Cursor on URI after multibyte characters":
    # "日本語 " = 4 runes, URL at runes 4..22
    let result = extractUriAtPosition("日本語 https://example.com here", 10)
    check result.isSome
    check result.get == "https://example.com"

  test "Cursor on multibyte text before URI":
    let result = extractUriAtPosition("日本語 https://example.com here", 2)
    check result.isNone

suite "extractFilePathAtPosition":
  test "Absolute path":
    let result = extractFilePathAtPosition("open /home/user/file.txt here", 10)
    check result.isSome
    check result.get == "/home/user/file.txt"

  test "Relative path with ./":
    let result = extractFilePathAtPosition("edit ./src/main.nim now", 10)
    check result.isSome
    check result.get == "./src/main.nim"

  test "Relative path with ../":
    let result = extractFilePathAtPosition("see ../README.md for info", 8)
    check result.isSome
    check result.get == "../README.md"

  test "Home path with ~":
    let result = extractFilePathAtPosition("at ~/documents/note.txt here", 5)
    check result.isSome
    check result.get == "~/documents/note.txt"

  test "Path at start of line":
    let result = extractFilePathAtPosition("/etc/hosts is important", 5)
    check result.isSome
    check result.get == "/etc/hosts"

  test "Path at end of line":
    let result = extractFilePathAtPosition("edit ./main.nim", 10)
    check result.isSome
    check result.get == "./main.nim"

  test "Bare filename without path prefix":
    let result = extractFilePathAtPosition("open foo.txt now", 7)
    check result.isNone

  test "Path inside quotes":
    let result = extractFilePathAtPosition("""open "/tmp/my file.txt" done""", 8)
    check result.isSome
    check result.get == "/tmp/my"

  test "Not a path":
    let result = extractFilePathAtPosition("just some text", 5)
    check result.isNone

  test "Cursor out of bounds":
    let result = extractFilePathAtPosition("short", 10)
    check result.isNone

  test "Empty string":
    let result = extractFilePathAtPosition("", 0)
    check result.isNone

  test "Path after multibyte characters":
    # "日本語 " = 4 runes, path at rune 4
    let result = extractFilePathAtPosition("日本語 /home/user/file.txt here", 10)
    check result.isSome
    check result.get == "/home/user/file.txt"

suite "isLocalFileUri":
  test "file:// URI":
    check isLocalFileUri("file:///tmp/test.txt") == true

  test "http:// URI":
    check isLocalFileUri("http://example.com") == false

  test "Plain path":
    check isLocalFileUri("/tmp/test.txt") == false

suite "isExternalUri":
  test "http":
    check isExternalUri("http://example.com") == true

  test "https":
    check isExternalUri("https://example.com") == true

  test "mailto":
    check isExternalUri("mailto:user@example.com") == true

  test "ftp":
    check isExternalUri("ftp://files.example.com") == true

  test "ssh":
    check isExternalUri("ssh://git@github.com") == true

  test "file":
    check isExternalUri("file:///tmp/test.txt") == false

  test "Plain text":
    check isExternalUri("just text") == false

suite "fileUriToPath":
  test "file:// URI":
    check fileUriToPath("file:///home/user/test.txt") == "/home/user/test.txt"

  test "Plain path passthrough":
    check fileUriToPath("/tmp/test.txt") == "/tmp/test.txt"

  test "Empty string":
    check fileUriToPath("") == ""
