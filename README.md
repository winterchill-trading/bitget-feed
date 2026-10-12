# bitget-feed

Read-only public market data from Bitget's v2 websocket, normalized to the
[market-data](https://github.com/winterchill-trading/market-data) types and exposed as a
`Market_data.Feed.t`. No API keys, no order entry. Built with OxCaml and the Jane Street
stack (Core, Async).

- `Bitget_feed.Config`: endpoint (mainnet `wss://ws.bitget.com/v2/ws/public` or a custom
  URL) and instrument type (default `USDT-FUTURES`).
- `Bitget_feed.Wire`: yojson types for pushes, acks and errors.
- `Bitget_feed.Normalizer`: pure frame -> events conversion, with a `Local_book` per
  `books` subscription for `seq`/`pseq` continuity (and the checksum, when sent).
- `Bitget_feed.Live_feed.create ?on_raw config ~symbols ~streams`: one socket per stream
  via [venue-net](https://github.com/winterchill-trading/venue-net), text `ping` every
  30 s, reconnect with resubscribe, unsubscribe/subscribe of a book that loses sync.

The wire protocol notes, with captured frames, are in
[docs/bitget-ws-spec.md](docs/bitget-ws-spec.md).

## Coverage

| Stream | Bitget channel | Event | Verified live (2026-10-12) |
|---|---|---|---|
| `trades` | `trade` | `Trade` per print, taker side | yes |
| `bbo` | `books1` | `Bbo` per push | yes |
| `l2` | `books` | `L2` snapshot, then deltas | yes (no gaps in 75 s, BTCUSDT + ETHUSDT) |
| `funding` | `ticker` | `Funding` when rate, next time, mark or index changes | yes |
| `private` | - | not supported (read-only feed) | - |

Verified on `USDT-FUTURES` (`BTCUSDT`, `ETHUSDT`); `SPOT` `BTCUSDT` also works for
trades, bbo and l2 (spot tickers carry no funding, so the funding stream stays empty).

## Usage

```
dune exec bitget-feed -- feed -symbol BTCUSDT -streams trades,bbo,l2,funding [-count N] [-seconds S]
```

Flags: `-symbol` (repeatable), `-streams` (comma separated, default all four), `-count`,
`-seconds`, `-inst-type` (`USDT-FUTURES` default, `SPOT`, ...), `-url`, `-raw` (raw
frames to stderr).

Live output (`TZ=UTC`, one command per stream, first events):

```
$ bitget-feed feed -symbol BTCUSDT -streams trades -count 2
(Trade
 ((instrument ((venue Bitget) (symbol BTCUSDT)))
  (exch_ts (2026-10-12 12:53:35.559000000Z))
  (recv_ts (2026-10-12 12:53:42.436292000Z)) (price 82853.8) (size 0.0037)
  (side Buy) (trade_id 1493523265781252096)))
(Trade
 ((instrument ((venue Bitget) (symbol BTCUSDT)))
  (exch_ts (2026-10-12 12:53:36.494000000Z))
  (recv_ts (2026-10-12 12:53:42.436292000Z)) (price 82853.7) (size 0.0706)
  (side Sell) (trade_id 1493523269702926336)))

$ bitget-feed feed -symbol BTCUSDT -streams bbo -count 1
(Bbo
 ((instrument ((venue Bitget) (symbol BTCUSDT)))
  (exch_ts (2026-10-12 12:53:43.740000000Z))
  (recv_ts (2026-10-12 12:53:43.793674000Z)) (bid_price 82850)
  (bid_size 5.1992) (ask_price 82850.1) (ask_size 2.5159)))

$ bitget-feed feed -symbol BTCUSDT -streams funding -count 1
(Funding
 ((instrument ((venue Bitget) (symbol BTCUSDT)))
  (exch_ts (2026-10-12 12:53:45.061000000Z))
  (recv_ts (2026-10-12 12:53:45.103977000Z)) (rate 0.0001)
  (next_funding_time (2026-10-12 16:00:00.000000000Z)) (mark_price 82850.6)
  (index_price 82886.375)))

$ bitget-feed feed -symbol BTCUSDT -streams l2 -count 1
(L2
 ((instrument ((venue Bitget) (symbol BTCUSDT)))
  (exch_ts (2026-10-12 12:53:46.301000000Z))
  (recv_ts (2026-10-12 12:53:46.635753000Z)) (kind Snapshot)
  (bids
   (((price 82850) (size 3.4738)) ((price 82849.9) (size 0.0016))
    ((price 82849.5) (size 0.0013)) ((price 82848.8) (size 0.003))
    ...
```

In ten-second runs per stream: 500 trades (50 of them the subscribe backlog), 775 bbo
updates, 1 snapshot plus 99 deltas on l2, 180 funding records.

## Symbol conventions

- Symbols are Bitget's own `instId`: `BTCUSDT`, `ETHUSDT`. The same name exists on spot
  and USDT futures; the market is chosen by `instType` in `Config`, not by the symbol.
- Instruments are `bitget:<instId>` (`Market_data.Venue.Bitget`). The instrument does
  not record the instrument type, so spot and perpetual `BTCUSDT` look the same
  downstream; use one feed per instrument type.

## Limitations

- The trade snapshot sent on subscribe (the last 50 trades) is emitted as normal
  trades, with `exch_ts` well before `recv_ts`; consumers de-duplicate by `trade_id`
  after a reconnect.
- `bbo` comes from `books1`, so its sizes are the full top level; `ticker` also carries
  bid/ask but is slower (~100 ms) and is used only for funding.
- `books` deltas are passed through as received; the local book only checks continuity.
  The live channel currently sends no `checksum`; the feed verifies it only when present.
- Funding `exch_ts` is the ticker's `ts`; `rate` is per funding interval, as
  sent. Bitget sends no separate funding event at settlement.
- `COIN-FUTURES` symbols tried (`BTCUSD`, `ETHUSD`) were rejected by the v2 endpoint
  (code 30001); only `USDT-FUTURES` and `SPOT` are verified.
- Feed.S has no stream for open interest or liquidations, which Bitget also publishes.
