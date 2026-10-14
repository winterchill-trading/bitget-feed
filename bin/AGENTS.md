# AGENTS.md (bin/)

`bitget-feed` executable with one subcommand, `feed`: `-symbol`, `-streams` (`trades`, `bbo`,
`l2`, `funding`), `-count`, `-seconds`, `-inst-type` and `-raw` (print the raw frames).

- Symbols are Bitget `instId`s. The market is chosen by `-inst-type`, not by the symbol.
- Build: `dune build --root .. @bitget-feed/all` from the repository root.
