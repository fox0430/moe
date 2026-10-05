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

## Routes each `SourceLanguage` to its lexer. No lexer imports this module,
## so it can import all of them.

import
  tokenizer, syntax_astro, syntax_c, syntax_commit_edit_msg, syntax_cpp, syntax_csharp,
  syntax_diff, syntax_dockerfile, syntax_fish, syntax_git_rebase_todo, syntax_gitignore,
  syntax_go, syntax_haskell, syntax_html, syntax_hyprland, syntax_java,
  syntax_javascript, syntax_latex, syntax_lisp, syntax_log, syntax_lua, syntax_markdown,
  syntax_nim, syntax_python, syntax_rust, syntax_shell, syntax_tcl, syntax_toml,
  syntax_yaml, syntax_json, syntax_jsonc, syntax_typescript, syntax_xml, syntax_zsh

proc languageNextToken(g: var GeneralTokenizer, lang: SourceLanguage) =
  case lang
  of langNone, langMarkdown:
    # Markdown goes through `fencedMarkdownNextToken`, so a fence never recurses.
    discard
  of langAstro:
    g.astroNextToken
  of langC:
    g.cNextToken
  of langCommitEditMsg:
    g.commitEditMsgNextToken
  of langCpp:
    g.cppNextToken
  of langCsharp:
    g.csharpNextToken
  of langDiff:
    g.diffNextToken
  of langDockerfile:
    g.dockerfileNextToken
  of langFish:
    g.fishNextToken
  of langGitRebaseTodo:
    g.gitRebaseTodoNextToken
  of langGitignore:
    g.gitignoreNextToken
  of langGo:
    g.goNextToken
  of langHaskell:
    g.haskellNextToken
  of langHtml:
    g.htmlNextToken
  of langHyprland:
    g.hyprlandNextToken
  of langJava:
    g.javaNextToken
  of langJavaScript, langJsx:
    g.javaScriptNextToken
  of langLatex:
    g.latexNextToken
  of langLisp:
    g.lispNextToken
  of langLog:
    g.logNextToken
  of langLua:
    g.luaNextToken
  of langNim:
    g.nimNextToken
  of langPython:
    g.pythonNextToken
  of langRust:
    g.rustNextToken
  of langShell:
    g.shellNextToken
  of langTcl:
    g.tclNextToken
  of langToml:
    g.tomlNextToken
  of langYaml:
    g.yamlNextToken
  of langJson:
    g.jsonNextToken
  of langJsonc:
    g.jsoncNextToken
  of langTypeScript, langTsx:
    g.typescriptNextToken
  of langXml:
    g.xmlNextToken
  of langZsh:
    g.zshNextToken

proc fencedMarkdownNextToken(g: var GeneralTokenizer) =
  let sub = g.codeBlockDelegate
  if sub in {langNone, langMarkdown}:
    g.markdownNextToken
  else:
    g.lexCodeBlockBody:
      g.languageNextToken(sub)

proc getNextToken*(g: var GeneralTokenizer, lang: SourceLanguage) =
  let
    startPos = g.pos
    startState = g.state
  if lang == langMarkdown:
    g.fencedMarkdownNextToken
  else:
    g.languageNextToken(lang)

  if g.kind != gtEof and g.pos <= startPos and g.state == startState:
    # A non-EOF token must consume input or change `state` (YAML's zero-consume
    # transitions). The lexers' own asserts are gone under `-d:danger`, so force
    # EOF rather than let the consumer loops spin forever.
    g.kind = gtEof
