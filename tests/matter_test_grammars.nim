when defined(moe.matter) or defined(features.moe.matter):
  import std/[json, strutils]
  import ../src/moepkg/syntax/[matter_backend, tokenizer]

  const
    NimMatterGrammar* =
      """
{
  "name": "Nim test grammar",
  "scopeName": "source.nim",
  "patterns": [
    {"include": "#blockComment"},
    {"match": "#.*$", "name": "comment.line.number-sign.nim"},
    {"match": "\\b(true|false)\\b", "name": "constant.language.boolean.nim"},
    {"match": "\\b(proc|let|discard)\\b", "name": "keyword.nim"},
    {"match": "\\b[0-9]+\\b", "name": "constant.numeric.nim"}
  ],
  "repository": {
    "blockComment": {
      "begin": "#\\[",
      "end": "\\]#",
      "name": "comment.block.nim",
      "patterns": [{"include": "#blockComment"}]
    }
  }
}
"""

    JsoncMatterGrammar* =
      """
{
  "name": "JSONC test grammar",
  "scopeName": "source.json.comments",
  "patterns": [
    {"match": "//.*$", "name": "comment.line.double-slash.jsonc"},
    {"match": "\\b(true|false|null)\\b", "name": "constant.language.jsonc"}
  ]
}
"""

    MarkdownMatterGrammar* =
      """
{
  "name": "Markdown test grammar",
  "scopeName": "text.html.markdown",
  "patterns": [
    {
      "begin": "^(```|~~~).*$",
      "end": "^\\1\\s*$",
      "name": "markup.fenced_code.block.markdown"
    }
  ]
}
"""

    HtmlMatterGrammar* =
      """
{
  "name": "HTML test grammar",
  "scopeName": "text.html.basic",
  "patterns": [
    {"match": "<!--.*?-->", "name": "comment.block.html"},
    {
      "begin": "(</?)([A-Za-z][A-Za-z0-9:-]*)",
      "beginCaptures": {
        "1": {"name": "punctuation.definition.tag.begin.html"},
        "2": {"name": "entity.name.tag.html"}
      },
      "end": "/?>",
      "endCaptures": {"0": {"name": "punctuation.definition.tag.end.html"}},
      "patterns": [
        {"begin": "\"", "end": "\"", "name": "string.quoted.double.html"},
        {"begin": "'", "end": "'", "name": "string.quoted.single.html"},
        {"match": "[A-Za-z_:][A-Za-z0-9_:.-]*", "name": "entity.other.attribute-name.html"}
      ]
    }
  ]
}
"""

  proc newScopedTestMatterGrammarSet*(scopes: openArray[string]): MatterGrammarSet =
    ## TextMate permits multiple scope names on a rule, from outermost to innermost.
    ## Exercise classification through the public tokenizer without bundling grammars.
    let grammar =
      %*{
        "scopeName": "source.scope-test",
        "patterns": [{"match": "token", "name": scopes.join(" ")}],
      }
    newMatterGrammarSet(
      [
        MatterGrammarSource(
          content: $grammar, path: "scopes.tmLanguage.json", language: langNim
        )
      ]
    )

  proc newTestMatterGrammarSet*(): MatterGrammarSet =
    newMatterGrammarSet(
      [
        MatterGrammarSource(
          content: NimMatterGrammar, path: "nim.tmLanguage.json", language: langNim
        ),
        MatterGrammarSource(
          content: JsoncMatterGrammar,
          path: "jsonc.tmLanguage.json",
          language: langJsonc,
        ),
        MatterGrammarSource(
          content: MarkdownMatterGrammar,
          path: "markdown.tmLanguage.json",
          language: langMarkdown,
        ),
        MatterGrammarSource(
          content: HtmlMatterGrammar, path: "html.tmLanguage.json", language: langHtml
        ),
      ]
    )
