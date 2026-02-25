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

import std/[unittest, json, options, strutils, os, tables]

import ../src/moepkg/color {.all.}
import ../src/moepkg/theme
import ../src/moepkg/vscode_theme {.all.}

suite "vscode_theme - VsCodeFlavor enum":
  test "enum values":
    check $VsCodeFlavor.VSCodium == "VSCodium"
    check $VsCodeFlavor.CodeOss == "CodeOss"
    check $VsCodeFlavor.VSCode == "VSCode"

suite "vscode_theme - colorFromNode":
  test "nil node returns TerminalDefaultRgb":
    let result = colorFromNode(nil)
    check result == TerminalDefaultRgb

  test "valid hex color with # prefix":
    let node = %"#ff0000"
    let result = colorFromNode(node)
    check result.red == 255
    check result.green == 0
    check result.blue == 0

  test "valid hex color - green":
    let node = %"#00ff00"
    let result = colorFromNode(node)
    check result.red == 0
    check result.green == 255
    check result.blue == 0

  test "valid hex color - blue":
    let node = %"#0000ff"
    let result = colorFromNode(node)
    check result.red == 0
    check result.green == 0
    check result.blue == 255

  test "valid hex color - mixed":
    let node = %"#1a2b3c"
    let result = colorFromNode(node)
    check result.red == 0x1a
    check result.green == 0x2b
    check result.blue == 0x3c

  test "hex color with alpha (RRGGBBAA format) - alpha is ignored":
    let node = %"#ff000080"
    let result = colorFromNode(node)
    check result.red == 255
    check result.green == 0
    check result.blue == 0

  test "invalid hex color - too short":
    let node = %"#fff"
    let result = colorFromNode(node)
    check result == TerminalDefaultRgb

  test "invalid hex color - no prefix":
    let node = %"ff0000"
    let result = colorFromNode(node)
    check result == TerminalDefaultRgb

  test "invalid hex color - invalid characters":
    let node = %"#gggggg"
    let result = colorFromNode(node)
    check result == TerminalDefaultRgb

  test "empty string returns TerminalDefaultRgb":
    let node = %""
    let result = colorFromNode(node)
    check result == TerminalDefaultRgb

  test "non-string node returns TerminalDefaultRgb":
    let node = %123
    let result = colorFromNode(node)
    check result == TerminalDefaultRgb

suite "vscode_theme - isCurrentVsCodeThemePackage":
  test "returns true when theme label matches":
    let json = %*{
      "contributes": {
        "themes": [
          {"label": "Dark+ (default dark)", "path": "./themes/dark_plus.json"},
          {"label": "Light+ (default light)", "path": "./themes/light_plus.json"},
        ]
      }
    }
    check isCurrentVsCodeThemePackage(json, "Dark+ (default dark)")
    check isCurrentVsCodeThemePackage(json, "Light+ (default light)")

  test "returns false when theme label does not match":
    let json = %*{
      "contributes": {
        "themes": [{"label": "Dark+ (default dark)", "path": "./themes/dark_plus.json"}]
      }
    }
    check not isCurrentVsCodeThemePackage(json, "Monokai")

  test "returns false when contributes is missing":
    let json = %*{"name": "some-extension"}
    check not isCurrentVsCodeThemePackage(json, "Dark+")

  test "returns false when themes array is missing":
    let json = %*{"contributes": {"languages": []}}
    check not isCurrentVsCodeThemePackage(json, "Dark+")

  test "returns false when themes is not an array":
    let json = %*{"contributes": {"themes": "not an array"}}
    check not isCurrentVsCodeThemePackage(json, "Dark+")

  test "returns true when theme id matches":
    let json = %*{
      "contributes": {
        "themes": [
          {
            "label": "%darkModernThemeLabel%",
            "id": "Default Dark Modern",
            "path": "./themes/dark_modern.json",
          }
        ]
      }
    }
    check isCurrentVsCodeThemePackage(json, "Default Dark Modern")

  test "returns true when theme id matches but label is NLS placeholder":
    let json = %*{
      "contributes": {
        "themes": [
          {
            "label": "%darkPlusColorThemeLabel%",
            "id": "Default Dark+",
            "path": "./themes/dark_plus.json",
          }
        ]
      }
    }
    check isCurrentVsCodeThemePackage(json, "Default Dark+")

  test "returns false when theme has no label or id":
    let json = %*{"contributes": {"themes": [{"path": "./themes/dark.json"}]}}
    check not isCurrentVsCodeThemePackage(json, "Dark+")

suite "vscode_theme - makeColorThemeFromVSCodeThemeFile":
  test "basic theme with editor foreground and background":
    let themeJson = %*{
      "colors": {"editor.foreground": "#d4d4d4", "editor.background": "#1e1e1e"},
      "tokenColors": [],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    # Check foreground is applied to default
    check result[EditorColorPairIndex.default].foreground.rgb.red == 0xd4
    check result[EditorColorPairIndex.default].foreground.rgb.green == 0xd4
    check result[EditorColorPairIndex.default].foreground.rgb.blue == 0xd4

    # Check background is applied to default
    check result[EditorColorPairIndex.default].background.rgb.red == 0x1e
    check result[EditorColorPairIndex.default].background.rgb.green == 0x1e
    check result[EditorColorPairIndex.default].background.rgb.blue == 0x1e

  test "keyword token color":
    let themeJson = %*{
      "colors": {},
      "tokenColors": [{"scope": "keyword", "settings": {"foreground": "#569cd6"}}],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.keyword].foreground.rgb.red == 0x56
    check result[EditorColorPairIndex.keyword].foreground.rgb.green == 0x9c
    check result[EditorColorPairIndex.keyword].foreground.rgb.blue == 0xd6

  test "string token color":
    let themeJson = %*{
      "colors": {},
      "tokenColors": [{"scope": "string", "settings": {"foreground": "#ce9178"}}],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.stringLit].foreground.rgb.red == 0xce
    check result[EditorColorPairIndex.stringLit].foreground.rgb.green == 0x91
    check result[EditorColorPairIndex.stringLit].foreground.rgb.blue == 0x78
    # Also affects charLit and lspString
    check result[EditorColorPairIndex.charLit].foreground.rgb ==
      result[EditorColorPairIndex.stringLit].foreground.rgb

  test "comment token color":
    let themeJson = %*{
      "colors": {},
      "tokenColors": [{"scope": "comment", "settings": {"foreground": "#6a9955"}}],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.comment].foreground.rgb.red == 0x6a
    check result[EditorColorPairIndex.comment].foreground.rgb.green == 0x99
    check result[EditorColorPairIndex.comment].foreground.rgb.blue == 0x55
    # Also affects longComment
    check result[EditorColorPairIndex.longComment].foreground.rgb ==
      result[EditorColorPairIndex.comment].foreground.rgb

  test "constant.numeric token color affects all number types":
    let themeJson = %*{
      "colors": {},
      "tokenColors":
        [{"scope": "constant.numeric", "settings": {"foreground": "#b5cea8"}}],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    let expectedRgb = Rgb(red: 0xb5, green: 0xce, blue: 0xa8)
    check result[EditorColorPairIndex.binNumber].foreground.rgb == expectedRgb
    check result[EditorColorPairIndex.decNumber].foreground.rgb == expectedRgb
    check result[EditorColorPairIndex.floatNumber].foreground.rgb == expectedRgb
    check result[EditorColorPairIndex.hexNumber].foreground.rgb == expectedRgb
    check result[EditorColorPairIndex.octNumber].foreground.rgb == expectedRgb

  test "entity.name.function token color":
    let themeJson = %*{
      "colors": {},
      "tokenColors":
        [{"scope": "entity.name.function", "settings": {"foreground": "#dcdcaa"}}],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    let expectedRgb = Rgb(red: 0xdc, green: 0xdc, blue: 0xaa)
    check result[EditorColorPairIndex.functionName].foreground.rgb == expectedRgb
    check result[EditorColorPairIndex.function].foreground.rgb == expectedRgb
    check result[EditorColorPairIndex.`method`].foreground.rgb == expectedRgb

  test "entity.name.type token color":
    let themeJson = %*{
      "colors": {},
      "tokenColors":
        [{"scope": "entity.name.type", "settings": {"foreground": "#4ec9b0"}}],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    let expectedRgb = Rgb(red: 0x4e, green: 0xc9, blue: 0xb0)
    check result[EditorColorPairIndex.typeName].foreground.rgb == expectedRgb
    check result[EditorColorPairIndex.className].foreground.rgb == expectedRgb
    check result[EditorColorPairIndex.interfaceName].foreground.rgb == expectedRgb
    check result[EditorColorPairIndex.builtinType].foreground.rgb == expectedRgb

  test "variable token color":
    let themeJson = %*{
      "colors": {},
      "tokenColors": [{"scope": "variable", "settings": {"foreground": "#9cdcfe"}}],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    let expectedRgb = Rgb(red: 0x9c, green: 0xdc, blue: 0xfe)
    check result[EditorColorPairIndex.specialVar].foreground.rgb == expectedRgb
    check result[EditorColorPairIndex.variable].foreground.rgb == expectedRgb

  test "line number colors":
    let themeJson = %*{
      "colors": {
        "editorLineNumber.foreground": "#858585",
        "editorLineNumber.activeForeground": "#c6c6c6",
      },
      "tokenColors": [],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.lineNum].foreground.rgb.red == 0x85
    check result[EditorColorPairIndex.lineNum].foreground.rgb.green == 0x85
    check result[EditorColorPairIndex.lineNum].foreground.rgb.blue == 0x85

    check result[EditorColorPairIndex.currentLineNum].foreground.rgb.red == 0xc6
    check result[EditorColorPairIndex.currentLineNum].foreground.rgb.green == 0xc6
    check result[EditorColorPairIndex.currentLineNum].foreground.rgb.blue == 0xc6

  test "status bar colors":
    let themeJson = %*{
      "colors": {"statusBar.foreground": "#ffffff", "statusBar.background": "#007acc"},
      "tokenColors": [],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    # Check status bar foreground
    check result[EditorColorPairIndex.statusLineNormalMode].foreground.rgb ==
      Rgb(red: 255, green: 255, blue: 255)

    # Check status bar background
    check result[EditorColorPairIndex.statusLineNormalMode].background.rgb.red == 0x00
    check result[EditorColorPairIndex.statusLineNormalMode].background.rgb.green == 0x7a
    check result[EditorColorPairIndex.statusLineNormalMode].background.rgb.blue == 0xcc

  test "tab colors":
    let themeJson = %*{
      "colors": {
        "tab.inactiveForeground": "#888888",
        "tab.inactiveBackground": "#2d2d2d",
        "tab.activeForeground": "#ffffff",
        "tab.activeBackground": "#1e1e1e",
      },
      "tokenColors": [],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.tab].foreground.rgb.red == 0x88
    check result[EditorColorPairIndex.tab].background.rgb.red == 0x2d
    check result[EditorColorPairIndex.currentTab].foreground.rgb.red == 0xff
    check result[EditorColorPairIndex.currentTab].background.rgb.red == 0x1e

  test "selection background":
    let themeJson =
      %*{"colors": {"editor.selectionBackground": "#264f78"}, "tokenColors": []}
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.selectArea].background.rgb.red == 0x26
    check result[EditorColorPairIndex.selectArea].background.rgb.green == 0x4f
    check result[EditorColorPairIndex.selectArea].background.rgb.blue == 0x78

  test "search highlight":
    let themeJson = %*{
      "colors": {"editor.findMatchHighlightBackground": "#ea5c0055"}, "tokenColors": []
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    # Alpha channel is ignored (only first 7 chars used)
    check result[EditorColorPairIndex.searchResult].background.rgb.red == 0xea
    check result[EditorColorPairIndex.searchResult].background.rgb.green == 0x5c
    check result[EditorColorPairIndex.searchResult].background.rgb.blue == 0x00

  test "current line background":
    let themeJson =
      %*{"colors": {"editor.lineHighlightBackground": "#ffffff0a"}, "tokenColors": []}
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.currentLineBg].background.rgb.red == 0xff
    check result[EditorColorPairIndex.currentLineBg].background.rgb.green == 0xff
    check result[EditorColorPairIndex.currentLineBg].background.rgb.blue == 0xff

  test "error and warning colors":
    let themeJson = %*{
      "colors": {
        "editorError.foreground": "#f14c4c",
        "editorWarning.foreground": "#cca700",
        "editorInfo.foreground": "#3794ff",
      },
      "tokenColors": [],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.errorMessage].foreground.rgb.red == 0xf1
    check result[EditorColorPairIndex.syntaxCheckErr].foreground.rgb.red == 0xf1

    check result[EditorColorPairIndex.warnMessage].foreground.rgb.red == 0xcc
    check result[EditorColorPairIndex.syntaxCheckWarn].foreground.rgb.red == 0xcc

    check result[EditorColorPairIndex.syntaxCheckInfo].foreground.rgb.red == 0x37

  test "git decoration colors":
    let themeJson = %*{
      "colors": {
        "gitDecoration.addedResourceForeground": "#81b88b",
        "gitDecoration.deletedResourceForeground": "#c74e39",
        "gitDecoration.modifiedResourceForeground": "#e2c08d",
      },
      "tokenColors": [],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.diffViewerAddedLine].foreground.rgb.red == 0x81
    check result[EditorColorPairIndex.sidebarGitAddedSign].foreground.rgb.red == 0x81

    check result[EditorColorPairIndex.diffViewerDeletedLine].foreground.rgb.red == 0xc7
    check result[EditorColorPairIndex.sidebarGitDeletedSign].foreground.rgb.red == 0xc7

    check result[EditorColorPairIndex.sidebarGitChangedSign].foreground.rgb.red == 0xe2

  test "whitespace foreground":
    let themeJson =
      %*{"colors": {"editorWhitespace.foreground": "#e3e4e229"}, "tokenColors": []}
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.whitespace].foreground.rgb.red == 0xe3
    check result[EditorColorPairIndex.whitespace].foreground.rgb.green == 0xe4
    check result[EditorColorPairIndex.whitespace].foreground.rgb.blue == 0xe2

  test "scope array in tokenColors":
    let themeJson = %*{
      "colors": {},
      "tokenColors": [
        {"scope": ["keyword", "keyword.control"], "settings": {"foreground": "#c586c0"}}
      ],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.keyword].foreground.rgb.red == 0xc5
    check result[EditorColorPairIndex.keyword].foreground.rgb.green == 0x86
    check result[EditorColorPairIndex.keyword].foreground.rgb.blue == 0xc0

  test "entity scope affects function and type":
    let themeJson = %*{
      "colors": {},
      "tokenColors": [{"scope": "entity", "settings": {"foreground": "#4fc1ff"}}],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    let expectedRgb = Rgb(red: 0x4f, green: 0xc1, blue: 0xff)
    check result[EditorColorPairIndex.functionName].foreground.rgb == expectedRgb
    check result[EditorColorPairIndex.typeName].foreground.rgb == expectedRgb
    check result[EditorColorPairIndex.boolean].foreground.rgb == expectedRgb
    check result[EditorColorPairIndex.builtin].foreground.rgb == expectedRgb

  test "constant scope affects numbers":
    let themeJson = %*{
      "colors": {},
      "tokenColors": [{"scope": "constant", "settings": {"foreground": "#b5cea8"}}],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    let expectedRgb = Rgb(red: 0xb5, green: 0xce, blue: 0xa8)
    check result[EditorColorPairIndex.binNumber].foreground.rgb == expectedRgb
    check result[EditorColorPairIndex.decNumber].foreground.rgb == expectedRgb

  test "operator token color":
    let themeJson = %*{
      "colors": {},
      "tokenColors":
        [{"scope": "keyword.operator", "settings": {"foreground": "#d4d4d4"}}],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.operator].foreground.rgb.red == 0xd4

  test "namespace token color":
    let themeJson = %*{
      "colors": {},
      "tokenColors":
        [{"scope": "entity.name.namespace", "settings": {"foreground": "#4ec9b0"}}],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.namespace].foreground.rgb.red == 0x4e

  test "decorator token color":
    let themeJson = %*{
      "colors": {},
      "tokenColors": [
        {
          "scope": "entity.name.function.decorator",
          "settings": {"foreground": "#dcdcaa"},
        }
      ],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.decorator].foreground.rgb.red == 0xdc
    check result[EditorColorPairIndex.attribute].foreground.rgb.red == 0xdc

  test "preprocessor token color from keyword.control.directive":
    let themeJson = %*{
      "colors": {},
      "tokenColors":
        [{"scope": "keyword.control.directive", "settings": {"foreground": "#c586c0"}}],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.preprocessor].foreground.rgb.red == 0xc5

  test "preprocessor token color from meta.preprocessor":
    let themeJson = %*{
      "colors": {},
      "tokenColors":
        [{"scope": "meta.preprocessor", "settings": {"foreground": "#569cd6"}}],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.preprocessor].foreground.rgb.red == 0x56

  test "macro token color":
    let themeJson = %*{
      "colors": {},
      "tokenColors":
        [{"scope": "entity.name.function.macro", "settings": {"foreground": "#dcdcaa"}}],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.`macro`].foreground.rgb.red == 0xdc

  test "enum token colors":
    let themeJson = %*{
      "colors": {},
      "tokenColors": [
        {"scope": "entity.name.type.enum", "settings": {"foreground": "#4ec9b0"}},
        {"scope": "variable.other.enummember", "settings": {"foreground": "#4fc1ff"}},
      ],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.enumName].foreground.rgb.red == 0x4e
    check result[EditorColorPairIndex.enumMember].foreground.rgb.red == 0x4f

  test "property token color":
    let themeJson = %*{
      "colors": {},
      "tokenColors":
        [{"scope": "variable.other.property", "settings": {"foreground": "#9cdcfe"}}],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.property].foreground.rgb.red == 0x9c

  test "parameter token color":
    let themeJson = %*{
      "colors": {},
      "tokenColors":
        [{"scope": "variable.parameter", "settings": {"foreground": "#9cdcfe"}}],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.parameter].foreground.rgb.red == 0x9c

  test "inlay hints colors":
    let themeJson = %*{
      "colors": {
        "editorInlayHint.foreground": "#969696", "editorInlayHint.background": "#1e1e1e"
      },
      "tokenColors": [],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.inlayHint].foreground.rgb.red == 0x96
    check result[EditorColorPairIndex.inlayHint].background.rgb.red == 0x1e

  test "code lens color":
    let themeJson =
      %*{"colors": {"editorCodeLens.foreground": "#999999"}, "tokenColors": []}
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.codeLens].foreground.rgb.red == 0x99

  test "cursor foreground":
    let themeJson =
      %*{"colors": {"editorCursor.foreground": "#aeafad"}, "tokenColors": []}
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.currentLineNum].foreground.rgb.red == 0xae
    check result[EditorColorPairIndex.backupManagerCurrentLine].foreground.rgb.red ==
      0xae
    check result[EditorColorPairIndex.configModeCurrentLine].foreground.rgb.red == 0xae

  test "popup window colors":
    let themeJson = %*{
      "colors": {
        "editorSuggestWidget.foreground": "#d4d4d4",
        "editorSuggestWidget.background": "#252526",
        "editorSuggestWidget.highlightForeground": "#0097fb",
        "editorSuggestWidget.selectedBackground": "#094771",
      },
      "tokenColors": [],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.popupWindow].foreground.rgb.red == 0xd4
    check result[EditorColorPairIndex.popupWindow].background.rgb.red == 0x25
    check result[EditorColorPairIndex.popupWinCurrentLine].foreground.rgb.red == 0x00
    check result[EditorColorPairIndex.popupWinCurrentLine].background.rgb.red == 0x09

  test "git conflict color":
    let themeJson = %*{
      "colors": {"gitDecoration.conflictingResourceForeground": "#e4676b"},
      "tokenColors": [],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.gitConflict].foreground.rgb.red == 0xe4
    check result[EditorColorPairIndex.replaceText].background.rgb.red == 0xe4

  test "hyperlink token color":
    let themeJson = %*{
      "colors": {},
      "tokenColors":
        [{"scope": "markup.underline.link", "settings": {"foreground": "#3794ff"}}],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.dir].foreground.rgb.red == 0x37
    check result[EditorColorPairIndex.pcLink].foreground.rgb.red == 0x37

  test "tab active border for highlight spaces":
    let themeJson = %*{"colors": {"tab.activeBorder": "#ff0000"}, "tokenColors": []}
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.highlightFullWidthSpace].background.rgb.red == 0xff
    check result[EditorColorPairIndex.highlightTrailingSpaces].background.rgb.red == 0xff

  test "line number background":
    let themeJson =
      %*{"colors": {"editorLineNumber.background": "#1e1e1e"}, "tokenColors": []}
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.lineNum].background.rgb.red == 0x1e

  test "resolveThemeIncludes merges colors and tokenColors":
    # Simulate include chain: child includes base
    let baseDir = getTempDir() / "moe_test_theme_include"
    createDir(baseDir)
    defer:
      removeDir(baseDir)

    # Write base theme
    let baseTheme = %*{
      "colors": {"editor.foreground": "#aaaaaa", "editor.background": "#111111"},
      "tokenColors": [{"scope": "comment", "settings": {"foreground": "#6a9955"}}],
    }
    writeFile(baseDir / "base.json", $baseTheme)

    # Child theme overrides foreground and adds keyword token
    let childTheme = %*{
      "include": "./base.json",
      "colors": {"editor.foreground": "#cccccc"},
      "tokenColors": [{"scope": "keyword", "settings": {"foreground": "#569cd6"}}],
    }

    let resolved = resolveThemeIncludes(childTheme, baseDir)
    let result = makeColorThemeFromVSCodeThemeFile(resolved)

    # Child overrides foreground
    check result[EditorColorPairIndex.default].foreground.rgb ==
      Rgb(red: 0xcc, green: 0xcc, blue: 0xcc)
    # Base provides background
    check result[EditorColorPairIndex.default].background.rgb ==
      Rgb(red: 0x11, green: 0x11, blue: 0x11)
    # Base provides comment color
    check result[EditorColorPairIndex.comment].foreground.rgb ==
      Rgb(red: 0x6a, green: 0x99, blue: 0x55)
    # Child provides keyword color
    check result[EditorColorPairIndex.keyword].foreground.rgb ==
      Rgb(red: 0x56, green: 0x9c, blue: 0xd6)

  test "empty theme returns DefaultColors base":
    let themeJson = %*{"colors": {}, "tokenColors": []}
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    # Should have DefaultColors values since no colors were specified
    check result[EditorColorPairIndex.default] ==
      DefaultColors[EditorColorPairIndex.default]

  test "missing tokenColors key":
    let themeJson = %*{"colors": {"editor.foreground": "#ffffff"}}
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.default].foreground.rgb.red == 0xff

  test "tokenColors with nil settings is skipped":
    let themeJson = %*{"colors": {}, "tokenColors": [{"scope": "keyword"}]}
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    # Should not crash and use default colors
    check result[EditorColorPairIndex.keyword] ==
      DefaultColors[EditorColorPairIndex.keyword]

  test "unnamed scope with bracketsForeground":
    let themeJson =
      %*{"colors": {}, "tokenColors": [{"settings": {"bracketsForeground": "#ffd700"}}]}
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)

    check result[EditorColorPairIndex.parenPair].foreground.rgb.red == 0xff
    check result[EditorColorPairIndex.parenPair].foreground.rgb.green == 0xd7
    check result[EditorColorPairIndex.parenPair].foreground.rgb.blue == 0x00

suite "vscode_theme - findTokenSettings":
  test "exact match":
    var t = initTable[string, JsonNode]()
    t["keyword"] = %*{"foreground": "#ff0000"}
    let r = t.findTokenSettings("keyword")
    check r != nil
    check r{"foreground"}.getStr == "#ff0000"

  test "exact match takes priority over parent":
    var t = initTable[string, JsonNode]()
    t["keyword"] = %*{"foreground": "#111111"}
    t["keyword.control"] = %*{"foreground": "#222222"}
    let r = t.findTokenSettings("keyword.control")
    check r != nil
    check r{"foreground"}.getStr == "#222222"

  test "parent scope match":
    var t = initTable[string, JsonNode]()
    t["entity"] = %*{"foreground": "#aaaaaa"}
    let r = t.findTokenSettings("entity.name.function")
    check r != nil
    check r{"foreground"}.getStr == "#aaaaaa"

  test "longest parent scope wins":
    var t = initTable[string, JsonNode]()
    t["entity"] = %*{"foreground": "#111111"}
    t["entity.name"] = %*{"foreground": "#222222"}
    let r = t.findTokenSettings("entity.name.function")
    check r != nil
    check r{"foreground"}.getStr == "#222222"

  test "child scope fallback":
    var t = initTable[string, JsonNode]()
    t["keyword.control"] = %*{"foreground": "#cc0000"}
    let r = t.findTokenSettings("keyword")
    check r != nil
    check r{"foreground"}.getStr == "#cc0000"

  test "shortest child scope wins":
    var t = initTable[string, JsonNode]()
    t["keyword.control"] = %*{"foreground": "#111111"}
    t["keyword.control.flow"] = %*{"foreground": "#222222"}
    let r = t.findTokenSettings("keyword")
    check r != nil
    check r{"foreground"}.getStr == "#111111"

  test "no match returns nil":
    var t = initTable[string, JsonNode]()
    t["string"] = %*{"foreground": "#ff0000"}
    let r = t.findTokenSettings("keyword")
    check r == nil

  test "siblings do not match":
    var t = initTable[string, JsonNode]()
    t["keyword.operator"] = %*{"foreground": "#ff0000"}
    let r = t.findTokenSettings("keyword.control")
    check r == nil

  test "theme with keyword.control applies to keyword in makeColorTheme":
    let themeJson = %*{
      "colors": {},
      "tokenColors":
        [{"scope": "keyword.control", "settings": {"foreground": "#c586c0"}}],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)
    check result[EditorColorPairIndex.keyword].foreground.rgb ==
      Rgb(red: 0xc5, green: 0x86, blue: 0xc0)

  test "theme with entity.name uses parent for entity.name.function lookup":
    let themeJson = %*{
      "colors": {},
      "tokenColors": [{"scope": "entity.name", "settings": {"foreground": "#4ec9b0"}}],
    }
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)
    check result[EditorColorPairIndex.functionName].foreground.rgb ==
      Rgb(red: 0x4e, green: 0xc9, blue: 0xb0)
    check result[EditorColorPairIndex.typeName].foreground.rgb ==
      Rgb(red: 0x4e, green: 0xc9, blue: 0xb0)

suite "vscode_theme - vsCodeSettingsFilePath":
  test "VSCodium settings path":
    let path = vsCodeSettingsFilePath(VsCodeFlavor.VSCodium)
    check path.endsWith("VSCodium/User/settings.json")

  test "CodeOss settings path":
    let path = vsCodeSettingsFilePath(VsCodeFlavor.CodeOss)
    check path.endsWith("Code - OSS/User/settings.json")

  test "VSCode settings path":
    let path = vsCodeSettingsFilePath(VsCodeFlavor.VSCode)
    check path.endsWith("Code/User/settings.json")

suite "vscode_theme - vsCodeUserExtensionsDir":
  test "VSCodium extensions dir":
    let path = vsCodeUserExtensionsDir(VsCodeFlavor.VSCodium)
    check path.endsWith(".vscode-oss/extensions")

  test "CodeOss extensions dir":
    let path = vsCodeUserExtensionsDir(VsCodeFlavor.CodeOss)
    check path.endsWith(".vscode-oss/extensions")

  test "VSCode extensions dir":
    let path = vsCodeUserExtensionsDir(VsCodeFlavor.VSCode)
    check path.endsWith(".vscode/extensions")

suite "vscode_theme - vsCodeDefaultExtensionsDir":
  test "VSCodium default extensions dir":
    let path = vsCodeDefaultExtensionsDir(VsCodeFlavor.VSCodium)
    check path == "/opt/vscodium-bin/resources/app/extensions"

  test "CodeOss default extensions dir":
    let path = vsCodeDefaultExtensionsDir(VsCodeFlavor.CodeOss)
    check path == "/usr/lib/code/extensions"

  test "VSCode default extensions dir":
    let path = vsCodeDefaultExtensionsDir(VsCodeFlavor.VSCode)
    check path == "/opt/visual-studio-code/resources/app/extensions"

suite "vscode_theme - vsCodeStateDbPath":
  test "VSCodium state db path":
    let path = vsCodeStateDbPath(VsCodeFlavor.VSCodium)
    check path.endsWith("VSCodium/User/globalStorage/state.vscdb")

  test "CodeOss state db path":
    let path = vsCodeStateDbPath(VsCodeFlavor.CodeOss)
    check path.endsWith("Code - OSS/User/globalStorage/state.vscdb")

  test "VSCode state db path":
    let path = vsCodeStateDbPath(VsCodeFlavor.VSCode)
    check path.endsWith("Code/User/globalStorage/state.vscdb")

suite "vscode_theme - readThemeNameFromStateDb":
  test "reads settingsId from valid data":
    let tmpFile = getTempDir() / "moe_test_statedb_valid"
    defer:
      removeFile(tmpFile)
    let data =
      "somegarbage\x00colorThemeData{\"settingsId\":\"Forest Mist\",\"other\":1}\x00more"
    writeFile(tmpFile, data)
    let result = readThemeNameFromStateDb(tmpFile)
    check result.isSome
    check result.get == "Forest Mist"

  test "returns none when file does not exist":
    let result = readThemeNameFromStateDb("/nonexistent/path/state.vscdb")
    check result.isNone

  test "returns none when colorThemeData pattern not found":
    let tmpFile = getTempDir() / "moe_test_statedb_nopattern"
    defer:
      removeFile(tmpFile)
    writeFile(tmpFile, "productIconThemeData{\"settingsId\":\"Default\"}")
    let result = readThemeNameFromStateDb(tmpFile)
    check result.isNone

  test "returns none when settingsId not found after colorThemeData":
    let tmpFile = getTempDir() / "moe_test_statedb_nosettings"
    defer:
      removeFile(tmpFile)
    writeFile(tmpFile, "colorThemeData{\"otherField\":\"value\"}")
    let result = readThemeNameFromStateDb(tmpFile)
    check result.isNone

  test "returns none for empty file":
    let tmpFile = getTempDir() / "moe_test_statedb_empty"
    defer:
      removeFile(tmpFile)
    writeFile(tmpFile, "")
    let result = readThemeNameFromStateDb(tmpFile)
    check result.isNone

  test "returns none when settingsId value is empty":
    let tmpFile = getTempDir() / "moe_test_statedb_emptyval"
    defer:
      removeFile(tmpFile)
    writeFile(tmpFile, "colorThemeData{\"settingsId\":\"\"}")
    let result = readThemeNameFromStateDb(tmpFile)
    check result.isNone

  test "ignores settingsId from productIconThemeData":
    let tmpFile = getTempDir() / "moe_test_statedb_multi"
    defer:
      removeFile(tmpFile)
    let data =
      "productIconThemeData{\"settingsId\":\"Default\"}\x00colorThemeData{\"settingsId\":\"Monokai\"}"
    writeFile(tmpFile, data)
    let result = readThemeNameFromStateDb(tmpFile)
    check result.isSome
    check result.get == "Monokai"

suite "vscode_theme - resolveThemeIncludes (edge cases)":
  test "returns original when no include field":
    let themeJson = %*{"colors": {"editor.foreground": "#ffffff"}, "tokenColors": []}
    let result = resolveThemeIncludes(themeJson, "/tmp")
    check result{"colors", "editor.foreground"}.getStr == "#ffffff"

  test "returns original when include is not a string":
    let themeJson = %*{"include": 123, "colors": {}, "tokenColors": []}
    let result = resolveThemeIncludes(themeJson, "/tmp")
    check result{"include"} != nil

  test "returns original when include file does not exist":
    let themeJson =
      %*{"include": "./nonexistent.json", "colors": {"editor.foreground": "#aaaaaa"}}
    let result = resolveThemeIncludes(themeJson, "/tmp/no_such_dir")
    check result{"colors", "editor.foreground"}.getStr == "#aaaaaa"

  test "multi-level include chain (A -> B -> C)":
    let baseDir = getTempDir() / "moe_test_multi_include"
    createDir(baseDir)
    defer:
      removeDir(baseDir)

    let themeC = %*{
      "colors": {"editor.background": "#111111"},
      "tokenColors": [{"scope": "comment", "settings": {"foreground": "#666666"}}],
    }
    writeFile(baseDir / "c.json", $themeC)

    let themeB = %*{
      "include": "./c.json",
      "colors": {"editor.foreground": "#bbbbbb"},
      "tokenColors": [],
    }
    writeFile(baseDir / "b.json", $themeB)

    let themeA = %*{
      "include": "./b.json",
      "colors": {"editor.foreground": "#aaaaaa"},
      "tokenColors": [{"scope": "keyword", "settings": {"foreground": "#ff0000"}}],
    }

    let resolved = resolveThemeIncludes(themeA, baseDir)
    check resolved{"colors", "editor.foreground"}.getStr == "#aaaaaa"
    check resolved{"colors", "editor.background"}.getStr == "#111111"
    check resolved{"tokenColors"}.len == 2

  test "base theme with missing colors key":
    let baseDir = getTempDir() / "moe_test_include_nocol"
    createDir(baseDir)
    defer:
      removeDir(baseDir)

    let baseTheme =
      %*{"tokenColors": [{"scope": "keyword", "settings": {"foreground": "#ff0000"}}]}
    writeFile(baseDir / "base.json", $baseTheme)

    let childTheme = %*{
      "include": "./base.json",
      "colors": {"editor.foreground": "#cccccc"},
      "tokenColors": [],
    }

    let resolved = resolveThemeIncludes(childTheme, baseDir)
    check resolved{"colors", "editor.foreground"}.getStr == "#cccccc"
    check resolved{"tokenColors"}.len == 1

  test "base theme with missing tokenColors key":
    let baseDir = getTempDir() / "moe_test_include_notok"
    createDir(baseDir)
    defer:
      removeDir(baseDir)

    let baseTheme = %*{"colors": {"editor.background": "#222222"}}
    writeFile(baseDir / "base.json", $baseTheme)

    let childTheme = %*{
      "include": "./base.json",
      "colors": {},
      "tokenColors": [{"scope": "string", "settings": {"foreground": "#00ff00"}}],
    }

    let resolved = resolveThemeIncludes(childTheme, baseDir)
    check resolved{"colors", "editor.background"}.getStr == "#222222"
    check resolved{"tokenColors"}.len == 1

  test "include file with invalid JSON returns original":
    let baseDir = getTempDir() / "moe_test_include_invalid"
    createDir(baseDir)
    defer:
      removeDir(baseDir)

    writeFile(baseDir / "bad.json", "not valid json{{{")

    let childTheme = %*{
      "include": "./bad.json",
      "colors": {"editor.foreground": "#dddddd"},
      "tokenColors": [],
    }

    let resolved = resolveThemeIncludes(childTheme, baseDir)
    check resolved{"colors", "editor.foreground"}.getStr == "#dddddd"

suite "vscode_theme - parseVsCodeThemeJson":
  test "loads theme file matching by label":
    let baseDir = getTempDir() / "moe_test_parsetheme"
    createDir(baseDir)
    defer:
      removeDir(baseDir)

    let themeContent = %*{"colors": {"editor.foreground": "#abcdef"}, "tokenColors": []}
    writeFile(baseDir / "my_theme.json", $themeContent)

    let packageJson =
      %*{"contributes": {"themes": [{"label": "My Theme", "path": "./my_theme.json"}]}}
    let result = parseVsCodeThemeJson(packageJson, "My Theme", baseDir / "package.json")
    check result.isSome
    check result.get{"colors", "editor.foreground"}.getStr == "#abcdef"

  test "returns none when theme name does not match":
    let baseDir = getTempDir() / "moe_test_parsetheme_nomatch"
    createDir(baseDir)
    defer:
      removeDir(baseDir)

    let packageJson =
      %*{"contributes": {"themes": [{"label": "Other Theme", "path": "./other.json"}]}}
    let result = parseVsCodeThemeJson(packageJson, "My Theme", baseDir / "package.json")
    check result.isNone

  test "returns none when theme file does not exist":
    let baseDir = getTempDir() / "moe_test_parsetheme_nofile"
    createDir(baseDir)
    defer:
      removeDir(baseDir)

    let packageJson = %*{
      "contributes": {"themes": [{"label": "My Theme", "path": "./nonexistent.json"}]}
    }
    let result = parseVsCodeThemeJson(packageJson, "My Theme", baseDir / "package.json")
    check result.isNone

  test "returns none when themes array is missing":
    let packageJson = %*{"contributes": {}}
    let result = parseVsCodeThemeJson(packageJson, "My Theme", "/tmp/package.json")
    check result.isNone

  test "returns none when path field is missing":
    let packageJson = %*{"contributes": {"themes": [{"label": "My Theme"}]}}
    let result = parseVsCodeThemeJson(packageJson, "My Theme", "/tmp/package.json")
    check result.isNone

  test "resolves include chain in loaded theme":
    let baseDir = getTempDir() / "moe_test_parsetheme_include"
    createDir(baseDir)
    defer:
      removeDir(baseDir)

    let baseTheme = %*{
      "colors": {"editor.background": "#000000"},
      "tokenColors": [{"scope": "comment", "settings": {"foreground": "#999999"}}],
    }
    writeFile(baseDir / "base.json", $baseTheme)

    let childTheme = %*{
      "include": "./base.json",
      "colors": {"editor.foreground": "#ffffff"},
      "tokenColors": [],
    }
    writeFile(baseDir / "child.json", $childTheme)

    let packageJson =
      %*{"contributes": {"themes": [{"label": "Child Theme", "path": "./child.json"}]}}
    let result =
      parseVsCodeThemeJson(packageJson, "Child Theme", baseDir / "package.json")
    check result.isSome
    check result.get{"colors", "editor.foreground"}.getStr == "#ffffff"
    check result.get{"colors", "editor.background"}.getStr == "#000000"
    check result.get{"tokenColors"}.len == 1

suite "vscode_theme - editor.background propagation":
  test "applies to all elements with default background":
    let themeJson = %*{"colors": {"editor.background": "#2d3142"}, "tokenColors": []}
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)
    let expectedBg = Rgb(red: 0x2d, green: 0x31, blue: 0x42)

    check result[EditorColorPairIndex.default].background.rgb == expectedBg
    check result[EditorColorPairIndex.keyword].background.rgb == expectedBg
    check result[EditorColorPairIndex.operator].background.rgb == expectedBg
    check result[EditorColorPairIndex.whitespace].background.rgb == expectedBg
    check result[EditorColorPairIndex.function].background.rgb == expectedBg
    check result[EditorColorPairIndex.`method`].background.rgb == expectedBg
    check result[EditorColorPairIndex.namespace].background.rgb == expectedBg
    check result[EditorColorPairIndex.className].background.rgb == expectedBg
    check result[EditorColorPairIndex.decorator].background.rgb == expectedBg
    check result[EditorColorPairIndex.parameter].background.rgb == expectedBg
    check result[EditorColorPairIndex.property].background.rgb == expectedBg
    check result[EditorColorPairIndex.enumName].background.rgb == expectedBg
    check result[EditorColorPairIndex.enumMember].background.rgb == expectedBg

  test "preserves non-default backgrounds":
    let themeJson = %*{"colors": {"editor.background": "#2d3142"}, "tokenColors": []}
    let result = makeColorThemeFromVSCodeThemeFile(themeJson)
    let themeBg = Rgb(red: 0x2d, green: 0x31, blue: 0x42)

    # Status line has non-black default (#61afef) - should NOT be changed
    check result[EditorColorPairIndex.statusLineNormalMode].background.rgb != themeBg
    # Select area has non-black default (#5c3d6e) - should NOT be changed
    check result[EditorColorPairIndex.selectArea].background.rgb != themeBg
    # Search result has non-black default (#be5046) - should NOT be changed
    check result[EditorColorPairIndex.searchResult].background.rgb != themeBg
    # Current line bg has non-black default (#3e4452) - should NOT be changed
    check result[EditorColorPairIndex.currentLineBg].background.rgb != themeBg
