name: Check `nph` formatting

on:
  pull_request:

jobs:
  nph:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Check `nph` formatting
        uses: arnetheduck/nph-action@v1
        with:
          version: latest
          options: "."
          fail: true
          suggest: true
