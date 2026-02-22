# Overview

moe adopts the mode and keybinding like vi/vim.
You can easily adapt if you have used vi/vim.
Currently you can use normal mode, visual mode, replace mode, insert mode, command mode, filer mode, terminal mode.

# Install and compile

## Requires
- [Nim](https://nim-lang.org) 2.0.10 or higher

### Install

I recommend using nimble to install:

```
# Latest developmental state inside Github repository
$ nimble install moe@#head
```

If you want to compile moe or use a version in development:

```
$ git clone https://github.com/fox0430/moe
$ cd moe
$ nimble install
```

### Debug build
```
$ cd moe
$ nimble build
```

### Release build
```
$ cd moe
$ nimble release
```

# Test

## Unit test

### Requires

- [nimlangserver](https://github.com/nim-lang/langserver)

```
nimble test
```

## Integration test

### Requires

[abduco](https://github.com/martanne/abduco)

[shpec](https://github.com/rylnd/shpec)

### Run integration test
```
cd moe
nimble install
shpec ./shpec.sh
```
