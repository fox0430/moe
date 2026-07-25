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

import std/[unittest, sets, strutils]

import ../src/moepkg/syntax/tokenizer

suite "tokenizer - TokenClass enum":
  test "TokenClass has expected values":
    check gtEof == low(TokenClass)
    check gtLogUuid == high(TokenClass)

  test "TokenClass ordering":
    check gtEof < gtNone
    check gtNone < gtWhitespace
    check gtKeyword < gtStringLit
    check gtRawData < gtCData

suite "tokenizer - SourceLanguage enum":
  test "SourceLanguage has expected values":
    check langNone == low(SourceLanguage)
    check langZsh == high(SourceLanguage)

  test "SourceLanguage includes all supported languages":
    check langNim in {langNone .. langTsx}
    check langRust in {langNone .. langTsx}
    check langPython in {langNone .. langTsx}
    check langJavaScript in {langNone .. langTsx}
    check langTypeScript in {langNone .. langTsx}

suite "tokenizer - sourceLanguageToStr":
  test "sourceLanguageToStr has correct mappings":
    check sourceLanguageToStr[langNone] == "none"
    check sourceLanguageToStr[langNim] == "Nim"
    check sourceLanguageToStr[langRust] == "Rust"
    check sourceLanguageToStr[langPython] == "Python"
    check sourceLanguageToStr[langC] == "C"
    check sourceLanguageToStr[langCpp] == "C++"
    check sourceLanguageToStr[langCsharp] == "C#"
    check sourceLanguageToStr[langJavaScript] == "JavaScript"
    check sourceLanguageToStr[langTypeScript] == "TypeScript"
    check sourceLanguageToStr[langJsx] == "JavaScriptReact"
    check sourceLanguageToStr[langTsx] == "TypeScriptReact"
    check sourceLanguageToStr[langHtml] == "HTML"
    check sourceLanguageToStr[langXml] == "XML"
    check sourceLanguageToStr[langJson] == "Json"
    check sourceLanguageToStr[langYaml] == "Yaml"
    check sourceLanguageToStr[langToml] == "Toml"
    check sourceLanguageToStr[langShell] == "Shell"
    check sourceLanguageToStr[langMarkdown] == "Markdown"
    check sourceLanguageToStr[langAstro] == "Astro"

  test "every language round-trips through getSourceLanguage":
    # Catches a name/enum drift for the members the spot-checks above miss.
    for lang in SourceLanguage:
      check getSourceLanguage(sourceLanguageToStr[lang]) == lang

  test "display names are unique":
    # A duplicate name would make getSourceLanguage return the earlier member.
    var seen: HashSet[string]
    for lang in SourceLanguage:
      let name = sourceLanguageToStr[lang].toLowerAscii
      check name notin seen
      seen.incl name

suite "tokenizer - getSourceLanguage":
  test "getSourceLanguage with exact case":
    check getSourceLanguage("Nim") == langNim
    check getSourceLanguage("Rust") == langRust
    check getSourceLanguage("Python") == langPython
    check getSourceLanguage("JavaScript") == langJavaScript

  test "getSourceLanguage case insensitive":
    check getSourceLanguage("nim") == langNim
    check getSourceLanguage("NIM") == langNim
    check getSourceLanguage("rust") == langRust
    check getSourceLanguage("RUST") == langRust
    check getSourceLanguage("python") == langPython
    check getSourceLanguage("PYTHON") == langPython

  test "getSourceLanguage with C variants":
    check getSourceLanguage("C") == langC
    check getSourceLanguage("c") == langC
    check getSourceLanguage("C++") == langCpp
    check getSourceLanguage("c++") == langCpp
    check getSourceLanguage("C#") == langCsharp
    check getSourceLanguage("c#") == langCsharp

  test "getSourceLanguage with common aliases":
    check getSourceLanguage("cpp") == langCpp
    check getSourceLanguage("cxx") == langCpp
    check getSourceLanguage("cs") == langCsharp
    check getSourceLanguage("csharp") == langCsharp
    check getSourceLanguage("js") == langJavaScript
    check getSourceLanguage("jsx") == langJsx
    check getSourceLanguage("ts") == langTypeScript
    check getSourceLanguage("tsx") == langTsx
    check getSourceLanguage("py") == langPython
    check getSourceLanguage("rs") == langRust
    check getSourceLanguage("sh") == langShell
    check getSourceLanguage("bash") == langShell
    check getSourceLanguage("yml") == langYaml
    check getSourceLanguage("docker") == langDockerfile
    check getSourceLanguage("md") == langMarkdown
    check getSourceLanguage("hs") == langHaskell
    check getSourceLanguage("tex") == langLatex
    check getSourceLanguage("latex") == langLatex

  test "getSourceLanguage returns langNone for unknown":
    check getSourceLanguage("unknown") == langNone
    check getSourceLanguage("") == langNone
    check getSourceLanguage("foo") == langNone

  test "getSourceLanguage with all languages":
    check getSourceLanguage("Astro") == langAstro
    check getSourceLanguage("Haskell") == langHaskell
    check getSourceLanguage("HTML") == langHtml
    check getSourceLanguage("Java") == langJava
    check getSourceLanguage("JavaScriptReact") == langJsx
    check getSourceLanguage("Markdown") == langMarkdown
    check getSourceLanguage("Shell") == langShell
    check getSourceLanguage("Toml") == langToml
    check getSourceLanguage("Yaml") == langYaml
    check getSourceLanguage("Json") == langJson
    check getSourceLanguage("TypeScript") == langTypeScript
    check getSourceLanguage("TypeScriptReact") == langTsx
    check getSourceLanguage("XML") == langXml

suite "tokenizer - initGeneralTokenizer":
  test "initGeneralTokenizer with empty string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("")
    check g.kind == low(TokenClass)
    check g.start == 0
    check g.length == 0
    check g.state == low(TokenClass)
    check g.pos == 0

  test "initGeneralTokenizer with simple code":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("hello")
    check g.kind == low(TokenClass)
    check g.start == 0
    check g.length == 0
    check g.state == low(TokenClass)
    check g.pos == 0

  test "initGeneralTokenizer does not skip initial whitespace":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("   hello")
    # Whitespace is NOT skipped during init - pos starts at 0
    check g.pos == 0
    # First token will be whitespace
    g.getNextToken(langNim)
    check g.kind == gtWhitespace
    check g.start == 0
    check g.length == 3

  test "initGeneralTokenizer does not skip tabs":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\t\thello")
    check g.pos == 0
    g.getNextToken(langNim)
    check g.kind == gtWhitespace
    check g.start == 0
    check g.length == 2

  test "initGeneralTokenizer does not skip mixed whitespace":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("  \t  hello")
    check g.pos == 0
    g.getNextToken(langNim)
    check g.kind == gtWhitespace
    check g.start == 0
    check g.length == 5

  test "initGeneralTokenizer initializes language-specific fields":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("test")
    check g.lang.jslike.templateLiteralDepth == 0
    check g.lang.jslike.braceDepthStack.len == 0
    check g.lang.jslike.inJsxMode == false
    check g.lang.jslike.jsxTagDepth == 0
    check g.lang.jslike.commentDepth == 0
    check g.lang.html.inComment == false
    check g.lang.html.inScript == false
    check g.lang.html.inStyle == false
    check g.lang.astro.inFrontmatter == false
    check g.lang.astro.firstLine == true
    check g.lang.markdown.firstLine == true

suite "tokenizer - generalNumber":
  test "generalNumber parses simple integer":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("123")
    let endPos = g.generalNumber(0)
    check endPos == 3
    check g.kind == gtDecNumber

  test "generalNumber parses integer with trailing chars":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("123abc")
    let endPos = g.generalNumber(0)
    check endPos == 3
    check g.kind == gtDecNumber

  test "generalNumber parses float with decimal":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("123.456")
    let endPos = g.generalNumber(0)
    check endPos == 7
    check g.kind == gtFloatNumber

  test "generalNumber parses float with exponent":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("123e10")
    let endPos = g.generalNumber(0)
    check endPos == 6
    check g.kind == gtFloatNumber

  test "generalNumber parses float with capital E exponent":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("123E10")
    let endPos = g.generalNumber(0)
    check endPos == 6
    check g.kind == gtFloatNumber

  test "generalNumber parses float with positive exponent":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("123e+10")
    let endPos = g.generalNumber(0)
    check endPos == 7
    check g.kind == gtFloatNumber

  test "generalNumber parses float with negative exponent":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("123e-10")
    let endPos = g.generalNumber(0)
    check endPos == 7
    check g.kind == gtFloatNumber

  test "generalNumber parses full float":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("123.456e+10")
    let endPos = g.generalNumber(0)
    check endPos == 11
    check g.kind == gtFloatNumber

  test "generalNumber with position offset":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("abc123")
    let endPos = g.generalNumber(3)
    check endPos == 6
    check g.kind == gtDecNumber

suite "tokenizer - generalStrLit":
  test "generalStrLit parses double-quoted string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\"")
    let endPos = g.generalStrLit(0)
    check endPos == 7
    check g.kind == gtStringLit

  test "generalStrLit parses single-quoted string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'hello'")
    let endPos = g.generalStrLit(0)
    check endPos == 7
    check g.kind == gtStringLit

  test "generalStrLit parses empty string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\"")
    let endPos = g.generalStrLit(0)
    check endPos == 2
    check g.kind == gtStringLit

  test "generalStrLit handles escape sequences":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\\nworld\"")
    let endPos = g.generalStrLit(0)
    check endPos == 14
    check g.kind == gtStringLit

  test "generalStrLit handles hex escape":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\\x41\"")
    let endPos = g.generalStrLit(0)
    check endPos == 6
    check g.kind == gtStringLit

  test "generalStrLit handles numeric escape":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\\123\"")
    let endPos = g.generalStrLit(0)
    check endPos == 6
    check g.kind == gtStringLit

  test "generalStrLit handles escaped quote":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\\\"world\"")
    let endPos = g.generalStrLit(0)
    check endPos == 14
    check g.kind == gtStringLit

  test "generalStrLit with unterminated string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello")
    let endPos = g.generalStrLit(0)
    check endPos == 6
    check g.kind == gtStringLit

suite "tokenizer - isKeyword":
  test "isKeyword finds keyword in sorted list":
    let keywords =
      ["break", "const", "continue", "else", "for", "if", "let", "return", "while"]
    check isKeyword(keywords, "if") >= 0
    check isKeyword(keywords, "let") >= 0
    check isKeyword(keywords, "return") >= 0

  test "isKeyword returns -1 for non-keyword":
    let keywords =
      ["break", "const", "continue", "else", "for", "if", "let", "return", "while"]
    check isKeyword(keywords, "foo") == -1
    check isKeyword(keywords, "bar") == -1
    check isKeyword(keywords, "") == -1

  test "isKeyword with empty keyword list":
    let keywords: seq[string] = @[]
    check isKeyword(keywords, "if") == -1

  test "isKeyword boundary keywords":
    let keywords =
      ["break", "const", "continue", "else", "for", "if", "let", "return", "while"]
    check isKeyword(keywords, "break") >= 0
    check isKeyword(keywords, "while") >= 0

suite "tokenizer - constants":
  test "eolChars contains expected characters":
    check '\0' in eolChars
    check '\n' in eolChars
    check '\r' in eolChars
    check ' ' notin eolChars

  test "lwsChars contains expected characters":
    check '\t' in lwsChars
    check ' ' in lwsChars
    check '\n' notin lwsChars

  test "opChars contains expected operators":
    check '+' in opChars
    check '-' in opChars
    check '*' in opChars
    check '/' in opChars
    check '=' in opChars
    check '<' in opChars
    check '>' in opChars
    check '!' in opChars
    check '&' in opChars
    check '|' in opChars
    check '^' in opChars
    check '~' in opChars
    check ':' in opChars

  test "symChars contains expected symbol characters":
    check 'a' in symChars
    check 'z' in symChars
    check 'A' in symChars
    check 'Z' in symChars
    check '0' in symChars
    check '9' in symChars
    check '_' in symChars
    check ' ' notin symChars
    check '!' notin symChars

  test "wsChars contains expected whitespace":
    check ' ' in wsChars
    check '\t' in wsChars
    check '\n' in wsChars
    check '\r' in wsChars

suite "tokenizer - getNextToken with langNim":
  test "getNextToken tokenizes Nim keywords":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("proc test")
    g.getNextToken(langNim)
    check g.kind == gtKeyword
    check g.length == 4

  test "getNextToken tokenizes Nim identifiers":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("myVar")
    g.getNextToken(langNim)
    check g.kind == gtIdentifier

  test "getNextToken tokenizes Nim comments":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("# comment")
    g.getNextToken(langNim)
    check g.kind == gtComment

  test "getNextToken tokenizes Nim string literals":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\"")
    g.getNextToken(langNim)
    check g.kind == gtStringLit

  test "getNextToken tokenizes Nim numbers":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("123")
    g.getNextToken(langNim)
    check g.kind == gtDecNumber

suite "tokenizer - getNextToken with langRust":
  test "getNextToken tokenizes Rust keywords":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("fn main")
    g.getNextToken(langRust)
    check g.kind == gtKeyword
    check g.length == 2

  test "getNextToken tokenizes Rust comments":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("// comment")
    g.getNextToken(langRust)
    check g.kind == gtComment

  test "getNextToken tokenizes Rust block comments":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/* comment */")
    g.getNextToken(langRust)
    check g.kind == gtLongComment

  test "getNextToken tokenizes Rust string literals":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\"")
    g.getNextToken(langRust)
    check g.kind == gtStringLit

  test "getNextToken tokenizes Rust identifiers":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("my_var")
    g.getNextToken(langRust)
    check g.kind == gtIdentifier

suite "tokenizer - getNextToken with langPython":
  test "getNextToken tokenizes Python keywords":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("def func")
    g.getNextToken(langPython)
    check g.kind == gtKeyword
    check g.length == 3

  test "getNextToken tokenizes Python comments":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("# comment")
    g.getNextToken(langPython)
    check g.kind == gtComment

  test "getNextToken tokenizes Python string literals":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\"")
    g.getNextToken(langPython)
    check g.kind == gtStringLit

  test "getNextToken tokenizes Python string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'single'")
    g.getNextToken(langPython)
    check g.kind == gtStringLit

suite "tokenizer - getNextToken with langJavaScript":
  test "getNextToken tokenizes JavaScript keywords":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("function test")
    g.getNextToken(langJavaScript)
    check g.kind == gtKeyword

  test "getNextToken tokenizes JavaScript comments":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("// comment")
    g.getNextToken(langJavaScript)
    check g.kind == gtComment

  test "getNextToken tokenizes JavaScript template literals":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("`template`")
    g.getNextToken(langJavaScript)
    check g.kind == gtLongStringLit

suite "tokenizer - getNextToken with langC":
  test "getNextToken tokenizes C keywords":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("int main")
    g.getNextToken(langC)
    check g.kind == gtKeyword

  test "getNextToken tokenizes C preprocessor":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#include")
    g.getNextToken(langC)
    check g.kind == gtPreprocessor

  test "getNextToken tokenizes C comments":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/* comment */")
    g.getNextToken(langC)
    check g.kind == gtLongComment

suite "tokenizer - getNextToken with langHtml":
  test "getNextToken tokenizes HTML tags":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<div>")
    g.getNextToken(langHtml)
    # First token is gtTagStart when `<` is followed by a letter
    check g.kind == gtTagStart

  test "getNextToken tokenizes HTML tag names":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<div>")
    g.getNextToken(langHtml)
    g.getNextToken(langHtml)
    # Second token is the tag name (may be gtKeyword for known tags)
    check g.kind in {gtTagStart, gtKeyword}

suite "tokenizer - getNextToken with langXml":
  test "getNextToken tokenizes XML tags":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<note>")
    g.getNextToken(langXml)
    # First token is gtTagStart when `<` is followed by a letter
    check g.kind == gtTagStart

  test "getNextToken tokenizes XML element names":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<note>")
    g.getNextToken(langXml)
    g.getNextToken(langXml)
    # Second token is the element name (gtKeyword for names following `<`)
    check g.kind == gtKeyword

suite "tokenizer - getNextToken with langJson":
  test "getNextToken tokenizes JSON string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"key\"")
    g.getNextToken(langJson)
    check g.kind == gtStringLit

  test "getNextToken tokenizes JSON number":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("123")
    g.getNextToken(langJson)
    check g.kind == gtDecNumber

  test "getNextToken tokenizes JSON boolean":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("true")
    g.getNextToken(langJson)
    check g.kind == gtKeyword

  test "getNextToken tokenizes JSON null":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("null")
    g.getNextToken(langJson)
    check g.kind == gtKeyword

suite "tokenizer - getNextToken with langYaml":
  test "getNextToken tokenizes YAML key":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("key: value")
    g.getNextToken(langYaml)
    # First token is gtNone or gtStringLit depending on context
    check g.kind in {gtNone, gtStringLit, gtKey}

  test "getNextToken tokenizes YAML comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("# comment")
    g.getNextToken(langYaml)
    check g.kind == gtComment

  test "getNextToken tokenizes YAML value":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("123")
    g.getNextToken(langYaml)
    # YAML tokenizer returns gtNone or gtDecNumber depending on context
    check g.kind in {gtNone, gtDecNumber, gtStringLit}

suite "tokenizer - getNextToken with langToml":
  test "getNextToken tokenizes TOML section":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[section]")
    g.getNextToken(langToml)
    check g.kind == gtTable

  test "getNextToken tokenizes TOML comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("# comment")
    g.getNextToken(langToml)
    check g.kind == gtComment

suite "tokenizer - getNextToken with langShell":
  test "getNextToken tokenizes Shell keywords":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("if then")
    g.getNextToken(langShell)
    check g.kind == gtKeyword

  test "getNextToken tokenizes Shell comments":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("# comment")
    g.getNextToken(langShell)
    check g.kind == gtComment

  test "getNextToken tokenizes Shell variables":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("$VAR")
    g.getNextToken(langShell)
    # $ is first tokenized as operator, then VAR as identifier
    check g.kind == gtOperator

suite "tokenizer - getNextToken with langMarkdown":
  test "getNextToken tokenizes Markdown heading marker":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("# Heading")
    g.getNextToken(langMarkdown)
    # Markdown tokenizer returns gtBuiltin for `#` at line start (heading)
    check g.kind == gtBuiltin

  test "getNextToken tokenizes Markdown code block marker":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("```code```")
    g.getNextToken(langMarkdown)
    # First token in code block is gtSpecialVar
    check g.kind == gtSpecialVar

suite "tokenizer - getNextToken iteration":
  test "getNextToken iterates through all tokens":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("fn main() { let x = 5; }")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.getNextToken(langRust)
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check tokens.len > 0
    check gtKeyword in tokens
    check gtIdentifier in tokens
    check gtDecNumber in tokens

  test "getNextToken handles whitespace":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a   b")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.getNextToken(langNim)
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtWhitespace in tokens

  test "getNextToken reaches gtEof":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("")
    g.getNextToken(langNim)
    check g.kind == gtEof

suite "tokenizer - GeneralTokenizer state":
  test "GeneralTokenizer preserves state between calls":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/* multi\nline\ncomment */")

    g.getNextToken(langRust)
    check g.kind == gtLongComment
    check g.length > 0

    # The state should track multi-line comment context
    check g.state in {gtLongComment, gtNone, gtEof}

  test "GeneralTokenizer tracks position correctly":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("abc def")

    g.getNextToken(langNim)
    check g.start == 0
    check g.length == 3

    g.getNextToken(langNim)
    check g.kind == gtWhitespace

    g.getNextToken(langNim)
    check g.length == 3

suite "tokenizer - langNone behavior":
  test "getNextToken with langNone does nothing":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("test")
    let startPos = g.pos
    g.getNextToken(langNone)
    check g.pos == startPos

suite "tokenizer - getNextToken with langTypeScript":
  test "getNextToken tokenizes TypeScript keywords":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("interface Foo")
    g.getNextToken(langTypeScript)
    check g.kind == gtKeyword

  test "getNextToken tokenizes TypeScript type annotations":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("let x: number")
    g.getNextToken(langTypeScript)
    check g.kind == gtKeyword

  test "getNextToken tokenizes TypeScript comments":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("// comment")
    g.getNextToken(langTypeScript)
    check g.kind == gtComment

suite "tokenizer - getNextToken with langTsx":
  test "getNextToken tokenizes TSX keywords":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("const Component")
    g.getNextToken(langTsx)
    check g.kind == gtKeyword

  test "getNextToken tokenizes TSX string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\"")
    g.getNextToken(langTsx)
    check g.kind == gtStringLit

suite "tokenizer - getNextToken with langJsx":
  test "getNextToken tokenizes JSX keywords":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("function App")
    g.getNextToken(langJsx)
    check g.kind == gtKeyword

  test "getNextToken tokenizes JSX string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'hello'")
    g.getNextToken(langJsx)
    check g.kind == gtStringLit

suite "tokenizer - getNextToken with langCpp":
  test "getNextToken tokenizes C++ keywords":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("class MyClass")
    g.getNextToken(langCpp)
    check g.kind == gtKeyword

  test "getNextToken tokenizes C++ comments":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("// comment")
    g.getNextToken(langCpp)
    check g.kind == gtComment

  test "getNextToken tokenizes C++ preprocessor":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#include <iostream>")
    g.getNextToken(langCpp)
    check g.kind == gtPreprocessor

suite "tokenizer - getNextToken with langCsharp":
  test "getNextToken tokenizes C# keywords":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("class Program")
    g.getNextToken(langCsharp)
    check g.kind == gtKeyword

  test "getNextToken tokenizes C# string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\"")
    g.getNextToken(langCsharp)
    check g.kind == gtStringLit

suite "tokenizer - getNextToken with langHaskell":
  test "getNextToken tokenizes Haskell keywords":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("module Main")
    g.getNextToken(langHaskell)
    check g.kind == gtKeyword

  test "getNextToken tokenizes Haskell comments":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("-- comment")
    g.getNextToken(langHaskell)
    check g.kind == gtComment

suite "tokenizer - getNextToken with langJava":
  test "getNextToken tokenizes Java keywords":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("public class")
    g.getNextToken(langJava)
    check g.kind == gtKeyword

  test "getNextToken tokenizes Java comments":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("// comment")
    g.getNextToken(langJava)
    check g.kind == gtComment

  test "getNextToken tokenizes Java block comments":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/* comment */")
    g.getNextToken(langJava)
    check g.kind == gtLongComment

suite "tokenizer - getNextToken with langAstro":
  test "getNextToken tokenizes Astro frontmatter":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("---")
    g.getNextToken(langAstro)
    check g.kind in {gtCommand, gtOperator, gtPunctuation, gtDirective}

  test "getNextToken tokenizes Astro text":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("Hello World")
    g.getNextToken(langAstro)
    check g.kind in {gtNone, gtIdentifier, gtOther}

suite "tokenizer - generalNumber edge cases":
  test "generalNumber with leading zero":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0123")
    let endPos = g.generalNumber(0)
    check endPos == 4
    check g.kind == gtDecNumber

  test "generalNumber with just zero":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0")
    let endPos = g.generalNumber(0)
    check endPos == 1
    check g.kind == gtDecNumber

  test "generalNumber with decimal starting with dot":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0.5")
    let endPos = g.generalNumber(0)
    check endPos == 3
    check g.kind == gtFloatNumber

  test "generalNumber stops at non-digit":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("123+456")
    let endPos = g.generalNumber(0)
    check endPos == 3
    check g.kind == gtDecNumber

  test "generalNumber with exponent without sign":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1e5")
    let endPos = g.generalNumber(0)
    check endPos == 3
    check g.kind == gtFloatNumber

suite "tokenizer - generalStrLit edge cases":
  test "generalStrLit with capital X hex escape":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\\X41\"")
    let endPos = g.generalStrLit(0)
    check endPos == 6
    check g.kind == gtStringLit

  test "generalStrLit with backslash at end":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"test\\")
    let endPos = g.generalStrLit(0)
    check endPos == 6
    check g.kind == gtStringLit

  test "generalStrLit with multiple escapes":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\\n\\t\\r\"")
    let endPos = g.generalStrLit(0)
    check endPos == 8
    check g.kind == gtStringLit

  test "generalStrLit with unicode-like content":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"日本語\"")
    let endPos = g.generalStrLit(0)
    check endPos > 2
    check g.kind == gtStringLit

  test "generalStrLit with single char hex escape":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\\xA\"")
    let endPos = g.generalStrLit(0)
    check endPos == 5
    check g.kind == gtStringLit

suite "tokenizer - UTF-8 and special characters":
  test "getNextToken handles UTF-8 identifiers":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("変数名")
    g.getNextToken(langNim)
    check g.kind == gtIdentifier

  test "getNextToken handles mixed ASCII and UTF-8":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("proc 日本語")
    g.getNextToken(langNim)
    check g.kind == gtKeyword

suite "tokenizer - multi-line token handling":
  test "unterminated string in Rust":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"line1")

    g.getNextToken(langRust)
    check g.kind == gtStringLit
    # Rust strings can span lines, so state parks at gtLongStringLit so
    # the next call resumes the same string.
    check g.state == gtLongStringLit
    check g.lang.rust.rawStringHashCount == 0

  test "multi-line comment in C":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/* comment")

    g.getNextToken(langC)
    check g.kind == gtLongComment

  test "nested block comments in Rust":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/* outer /* inner */ still comment */")

    g.getNextToken(langRust)
    check g.kind == gtLongComment

suite "tokenizer - empty and edge input":
  test "empty string returns gtEof":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("")
    g.getNextToken(langNim)
    check g.kind == gtEof

  test "whitespace only input":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("   ")
    # Whitespace is returned as a token, not skipped
    g.getNextToken(langNim)
    check g.kind == gtWhitespace

    g.getNextToken(langNim)
    check g.kind == gtEof

  test "newline handling":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a\nb")

    g.getNextToken(langNim)
    check g.kind == gtIdentifier

    g.getNextToken(langNim)
    check g.kind == gtWhitespace

    g.getNextToken(langNim)
    check g.kind == gtIdentifier

  test "tab handling":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a\tb")

    g.getNextToken(langNim)
    check g.kind == gtIdentifier

    g.getNextToken(langNim)
    check g.kind == gtWhitespace

suite "tokenizer - token extraction":
  test "extract token text using start and length":
    var g: GeneralTokenizer
    let code = "proc main"
    g.initGeneralTokenizer(code)

    g.getNextToken(langNim)
    check g.kind == gtKeyword
    check code[g.start ..< g.start + g.length] == "proc"

    g.getNextToken(langNim)
    check g.kind == gtWhitespace

    g.getNextToken(langNim)
    check g.kind == gtIdentifier
    check code[g.start ..< g.start + g.length] == "main"

  test "extract number token":
    var g: GeneralTokenizer
    let code = "let x = 42"
    g.initGeneralTokenizer(code)

    # Parse all tokens and find number
    var foundNumber = false
    var numberText = ""
    while true:
      g.getNextToken(langNim)
      if g.kind == gtEof:
        break
      if g.kind == gtDecNumber:
        foundNumber = true
        numberText = code[g.start ..< g.start + g.length]
        break

    check foundNumber
    check numberText == "42"

  test "extract string literal token":
    var g: GeneralTokenizer
    let code = "let s = \"hello\""
    g.initGeneralTokenizer(code)

    # Parse all tokens and find string
    var foundString = false
    var stringText = ""
    while true:
      g.getNextToken(langNim)
      if g.kind == gtEof:
        break
      if g.kind == gtStringLit:
        foundString = true
        stringText = code[g.start ..< g.start + g.length]
        break

    check foundString
    check stringText == "\"hello\""

suite "tokenizer - all TokenClass values used":
  test "gtOperator in Nim":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a + b")
    g.getNextToken(langNim)
    g.getNextToken(langNim)
    g.getNextToken(langNim)
    check g.kind == gtOperator

  test "gtPunctuation in Nim":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("()")
    g.getNextToken(langNim)
    check g.kind == gtPunctuation

  test "gtCharLit in Nim":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'a'")
    g.getNextToken(langNim)
    check g.kind == gtCharLit

  test "gtBuiltin in Rust":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("String")
    g.getNextToken(langRust)
    check g.kind == gtBuiltin

  test "gtBoolean in Rust":
    var g: GeneralTokenizer
    # Use false after whitespace to trigger gtBoolean
    g.initGeneralTokenizer("x false")
    var foundBoolean = false
    while true:
      g.getNextToken(langRust)
      if g.kind == gtEof:
        break
      if g.kind == gtBoolean:
        foundBoolean = true
        break
    check foundBoolean

suite "tokenizer - peek":
  test "peek looks ahead without advancing":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("abc")
    check g.peek(0) == 'b'
    check g.peek(0, 2) == 'c'

  test "peek past the buffer yields the NUL terminator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("ab")
    check g.peek(0, 2) == '\0'
    check g.peek(0, 5) == '\0'

suite "tokenizer - scanStringBody":
  test "consumes the closing quote":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"abc\"")
    g.kind = gtStringLit
    # position 1 is just past the opening quote.
    check g.scanStringBody(1, '"') == 5
    check g.state == low(TokenClass)

  test "single-quoted string works the same way":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'x'")
    g.kind = gtStringLit
    check g.scanStringBody(1, '\'') == 3

  test "stops at a line boundary without consuming it":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"ab\nrest")
    g.kind = gtStringLit
    check g.scanStringBody(1, '"') == 3
    check g.state == low(TokenClass)

  test "stops at EOF without consuming it":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"ab")
    g.kind = gtStringLit
    check g.scanStringBody(1, '"') == 3

  test "parks g.state on a backslash so the resume path takes over":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"a\\nb\"")
    g.kind = gtStringLit
    # Halts at the backslash (index 2) and parks the kind into state.
    check g.scanStringBody(1, '"') == 2
    check g.state == gtStringLit

  test "preserves a non-default token kind (JSON key)":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"k\\\"")
    g.kind = gtKey
    discard g.scanStringBody(1, '"')
    check g.state == gtKey

suite "tokenizer - scanRadixNumber":
  test "hexadecimal":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0xFF")
    check g.scanRadixNumber(0) == 4
    check g.kind == gtHexNumber

  test "binary":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0b1010")
    check g.scanRadixNumber(0) == 6
    check g.kind == gtBinNumber

  test "implicit octal":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0755")
    check g.scanRadixNumber(0) == 4
    check g.kind == gtOctNumber

  test "decimal falls through to generalNumber":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("42")
    check g.scanRadixNumber(0) == 2
    check g.kind == gtDecNumber

  test "float falls through to generalNumber":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("3.14")
    check g.scanRadixNumber(0) == 4
    check g.kind == gtFloatNumber

  test "lone zero is decimal":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0;")
    check g.scanRadixNumber(0) == 1
    check g.kind == gtDecNumber

  test "trailing suffix letters are left to the caller":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0xFFu")
    # The 'u' suffix is not consumed by the radix scanner.
    check g.scanRadixNumber(0) == 4
