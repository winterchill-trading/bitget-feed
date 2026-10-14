# AGENTS.md (bench/)

Two benchmarks, both on recorded frames from `test/fixtures`:

- `main.exe` times `Normalizer.frame` per recorded frame.
- `live.exe` writes the recorded trades frames through a loopback websocket and times delivery.

Numbers depend on the machine. Quote them with the machine and the command, and do not pin them in tests.
