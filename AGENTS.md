# AGENTS.md

## Purpose

Read-only public market data from Bitget's v2 websocket, normalized into `market-data` records
as a `Market_data.Feed.t`. No API keys and no order entry: the package never signs anything.

## Layout

| Path | Holds |
| --- | --- |
| `lib/` | Library `bitget_feed`: `Config`, `Wire`, `Local_book`, `Checksum`, `Normalizer`, `Live_feed`, `Raw_normalizer` (see `lib/AGENTS.md`) |
| `bin/` | `bitget-feed` executable: `feed` subcommand (see `bin/AGENTS.md`) |
| `bench/` | `main.exe` (normalizer per frame) and `live.exe` (websocket delivery) (see `bench/AGENTS.md`) |
| `test/` | Expect tests, allocation pins, fake-clock tests, loopback server, recorded minute (see `test/AGENTS.md`) |
| `docs/` | `bitget-ws-spec.md`: the channel shapes the normalizer reads (see `docs/AGENTS.md`) |
| `.github/` | CI workflow (see `.github/AGENTS.md`) |
| `dune-project`, `bitget-feed.opam` | Package metadata; the `.opam` file is generated from `dune-project` |

## Build, test, docs

Run from this directory. The workspace root `..` holds the sibling checkouts and the shared
`dune-workspace`.

```sh
opam exec --switch 5.2.0+ox -- dune build --root .. @bitget-feed/all
opam exec --switch 5.2.0+ox -- dune build --root .. @bitget-feed/runtest
DUNE_BUILD_DIR=_build-bitget-feed opam exec --switch 5.2.0+ox -- dune build --root .. @bitget-feed/all
```

The last line is for parallel work: a private build directory avoids the lock shared with
other repositories in the workspace.

Run the feed: `dune exec bitget-feed -- feed -symbol BTCUSDT -streams trades,bbo,l2,funding -count 100`.
Benchmarks: `dune exec bench/main.exe` and `dune exec bench/live.exe`.

Standalone (outside the workspace), pin the siblings from GitHub as the CI workflow does, then:

```sh
opam pin add -n -y fixed-decimal https://github.com/winterchill-trading/fixed-decimal.git
# repeat for exchange-core, parquet, market-data, venue-net (see .github/workflows/ci.yml)
opam install . --deps-only --with-test
dune build && dune test
```

## Conventions

- Formatting: `dune build --root .. @bitget-feed/fmt --auto-promote`, run after the tests pass.
  Never `dune fmt` at the workspace root; it reformats every sibling repository.
- Every module has an `.mli`. Use `open! Core`, labelled arguments and `ppx_jane`.
- `Normalizer` is pure: frame in, events out. Keep I/O and clocks in `Live_feed`, so the
  normalizer can be tested on recorded frames.
- Time comes from `?time_source` (default: the wall clock). Tests drive it with a fake clock.
- Minor words per message are pinned in `test/test_allocation.ml`.
- Add a short comment at any non-obvious choice, such as a resync rule or a pinned count.
- Document every public value in its `.mli` with odoc comments.

## Dependencies and dependents

- Depends on: `market-data`, `venue-net` (and `fixed-decimal`, `exchange-core`, `parquet` as
  transitive pins).
- Used by: `market-recorder`.
- CI pin order: `fixed-decimal`, `exchange-core`, `parquet`, `market-data`, `venue-net`.

## CI

`.github/workflows/ci.yml` runs the `ox-setup` action with the pins above (its opam switch is
cached between runs), then `dune build` and `dune test`. The `obj-magic` job calls the shared
reusable workflow. To check a run: `gh run list --limit 1`, then at most one
`gh run watch <id> --exit-status`. Do not poll in a loop.

## Pitfalls

- Bitget sends a backlog of recent trades on every subscribe, and batches arrive newest first.
  Consumers de-duplicate by trade id; do not count the backlog as new trades.
- Keepalive is the plain text frame `ping`, sent every 30 s (`Live_feed`); the reply is text `pong`.
- Deltas before the first snapshot are dropped; a break in `seq`/`pseq` drops the book and
  resubscribes it.
- The `books` channel carries no checksum in the live feed today; the checksum path is tested
  on recorded frames only.
- Bitget's v2 channel URLs redirect to newer docs. Capture live frames when a shape is in doubt.
- The instrument type is not recorded downstream, so spot and perpetual `BTCUSDT` look the
  same. Select the market with `Config.inst_type`.
- `Time_ns.Span.to_int63_ns` returns `Int63.t`; divisions need `Int63.( / )`.

## Where to read more

- `README.md` (coverage, gaps and reconnects, symbol conventions, limitations).
- `docs/bitget-ws-spec.md`.
- `../specs/repos/bitget-feed.md` for status and dependencies.
- `../specs/repos/market-data.md` for the record types this feed produces.
- Skills in `../oxcaml-claude-skills/skills/`: `async-http-websocket`, `oxcaml-performance`.
- `../oxcaml-claude-skills/AGENTS.md`: the workspace-wide guide.
- `../oxcaml-claude-skills/GOTCHAS.md`: the dated log these pitfalls come from.

## Never do

- Run `opam install`, `opam upgrade` or `opam pin` on the shared `5.2.0+ox` switch without a
  dry run first: `opam install --switch 5.2.0+ox --dry-run <pkg>`. Abort if the plan touches
  `ocaml-variants`, `core`, `base`, `async` or `ppx_jane`.
- Add API keys or order entry to this package. It is read-only by design.
- Publish, tag or release a version from this repository without the maintainers asking.
- Poll CI in a loop.
