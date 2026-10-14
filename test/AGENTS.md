# AGENTS.md (test/)

Tests for `bitget_feed`.

- `test_normalizer.ml`, `test_checksum.ml`, `test_wire.ml`: pure decoding and sequencing.
- `test_gaps_fake_clock.ml`, `test_reconnect_fake_clock.ml`: `Live_feed` on a synthetic clock.
- `loopback_server.ml` serves recorded frames over a local websocket for `test_live_feed.ml`.
- `test_rebuild_norm.ml` runs `Rebuild_norm` over the recorded minute and reads the logs back.
- `test/fixtures/bitget-BTCUSDT-*` is a trimmed mainnet minute in the recorder's raw format.
  Fixtures are data; do not edit them by hand.
- Run: `dune build --root .. @bitget-feed/runtest` from the repository root.
- Promote expect output with `dune promote` only after reading the diff.
