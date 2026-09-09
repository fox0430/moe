## Shared syntax-highlighting configuration types.

type
  HighlightBackend* = enum
    hbBuiltin = "builtin" ## Moe's built-in tokenizer
    hbMatter = "matter" ## Optional Matter TextMate grammar tokenizer

  TextMateGrammarError* = object of ValueError
    ## Invalid grammar input or unavailable Matter support at the public API.
