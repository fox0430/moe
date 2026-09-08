when defined(moe.matter):
  import ../src/moepkg/syntax/[matter_backend, tokenizer]

  const
    NimMatterGrammar* = """
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

    JsoncMatterGrammar* = """
{
  "name": "JSONC test grammar",
  "scopeName": "source.json.comments",
  "patterns": [
    {"match": "//.*$", "name": "comment.line.double-slash.jsonc"},
    {"match": "\\b(true|false|null)\\b", "name": "constant.language.jsonc"}
  ]
}
"""

    MarkdownMatterGrammar* = """
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
      ]
    )
