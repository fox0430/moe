[![](https://github.com/fox0430/moe/workflows/Build/badge.svg)](https://github.com/fox0430/moe/workflows/Build)
[![](https://github.com/fox0430/moe/workflows/CFF/badge.svg)](https://github.com/fox0430/moe/workflows/CFF)
[![](https://github.com/fox0430/moe/workflows/Tests/badge.svg)](https://github.com/fox0430/moe/workflows/Tests)
[![](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)

## moe

A command line based editor inspired by Vim written in Nim.

This project's goals are easily customizable, high productivity, user friendly, and high performance editor.

![moe](https://user-images.githubusercontent.com/15966436/146791140-e020a07f-7ca1-4bfd-a6a4-f20f4c7885db.png)

## Features

- Written in [Nim](https://nim-lang.org)

- Adopt GapBuffer

- UTF-8 and other encodings support (Incomplete)

- Vim like mode (Normal, Insert, Visual, Replace, Ex, Filer)

- Vim like keybinds

- Infinite undo/redo

- Syntax highlighting:

  - C
  - C++
  - C#
  - Haskell
  - Java
  - JavaScript
  - Markdown
  - Nim
  - Python
  - Rust
  - Shell languages:
    - Bash
  - TOML
  - YAML

- Auto-complete

- Configuration file (TOML)

- Configuration mode

- Live reload of the configuration file

- Vertical/Horizontal split window

- Tab line

- Indentation lines

- Auto close/delete paren

- Simple auto indent

- Incremental search

- Auto save

- Suggestions in ex mode

- TrueColor (24bit color)

- VSCode themes

- Build on save

- Multiple status line

- QuickRun

- Automatic backups

- Highlight current words

- Highlight/Delete trailing spaces

- Vim like register

- Git support

- Syntax checker

  - Nim

- Macros

- Language Server Protocol (WIP)

  - Diagnostics

  - Completion

  - Inlay Hints

  - Hover

  - Goto definition

  - Find References

  - Semantic Tokens

## Planned features

- Supports regular expression and PEG

- Supports EditorConfig

- Window management

- Snippets

- Spell checker

- Terminal

- Select data structures

- Edit files over ssh

- Fuzzy search

- Plugins

- Supports huge file

- Funny animation...

## Install

We recommend Linux environments.

### Requires

- [Nim](https://nim-lang.org) 1.6.2 or higher

- [Ncurses](https://invisible-island.net/ncurses) 6.1 or higher

- [xclip](https://github.com/astrand/xclip) v0.13 or higher (Option on GNU/Linux)

- [xsel](http://www.kfish.org/software/xsel/) (Option on GNU/Linux)

- [wl-clipboard](https://github.com/bugaevc/wl-clipboard) (Option on GNU/Linux)

```sh
# Latest developmental state inside Github repository
nimble install moe@#head
```

Check [detail](https://github.com/fox0430/moe/blob/develop/documents/overview.md)

## Usage

[Documents (Latest)](https://github.com/fox0430/moe/blob/develop/documents/index.md)

[Documents (Release)](https://github.com/fox0430/moe/blob/master/documents/index.md)

## The origin of the name
moe is a recursive acronym for "moe is an optimal editor".    
And one more, it comes from the Japanese slang 萌え(moe).

## Contributing, bug reports, feature request
Welcome❤

## Community

Ask me anything!

 - [Discord](https://discord.gg/UaJPnCF)

## License

GNU General Public License version 3
