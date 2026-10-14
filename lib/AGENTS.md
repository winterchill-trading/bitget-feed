# AGENTS.md (lib/)

Library `bitget_feed`: the public Bitget websocket feed and its normalizer.

- `Wire` decodes pushes, acks and errors. `Normalizer` turns one frame into `Market_data`
  events and is pure. `Local_book` keeps per-subscription `seq`/`pseq` continuity; `Checksum`
  verifies CRC32 over the top levels when the venue sends one.
- `Live_feed` owns the sockets: one per stream, the 30 s text ping, reconnect and resubscribe.
  `create_with_stats` also returns the `Stats.t` reader (frames, parse errors, reconnects).
- `Raw_normalizer` adapts `Normalizer` to `Market_data.Normalizer.S` for rebuilding event logs
  from recorded minutes.
- Build: `dune build --root .. @bitget-feed/all` from the repository root.
