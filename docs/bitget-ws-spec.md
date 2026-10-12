# Bitget v2 public websocket: the parts this feed uses

Sources: the classic (v2) websocket introduction at
`https://www.bitget.com/docs/classic/websocket/intro`, the depth channel description in
the current docs (`/docs/uta/websocket/public/Order-Book-Channel`, same `seq`/`pseq` rules),
and frames captured from the live endpoint on 2026-10-12. The per-channel v2 contract pages
now redirect to the unified account docs, so the sample frames below are real captures,
trimmed.

## Endpoint

| Purpose | URL |
|---|---|
| Public channels | `wss://ws.bitget.com/v2/ws/public` |
| Private channels (not used) | `wss://ws.bitget.com/v2/ws/private` |

No login is needed for public channels.

## Limits

- 300 connection requests per IP per 5 minutes, at most 100 connections per IP.
- 240 subscription requests per hour per connection, at most 1000 channels per connection;
  fewer than 50 channels per connection is recommended.
- At most 10 client messages per second per connection (`ping` strings and JSON requests
  both count); exceeding it disconnects, and repeated offenders get the IP blocked.
- A subscribe request's `args` must not exceed 4096 bytes.

## Keepalive

- The client sends the plain text frame `ping` every 30 seconds; the server answers with
  the plain text frame `pong` (not JSON).
- The server drops a connection that has sent no `ping` for 2 minutes.
- No `pong` means the connection is dead: reconnect and resubscribe.

## Subscribe

```json
{"op":"subscribe","args":[{"instType":"USDT-FUTURES","channel":"trade","instId":"BTCUSDT"}]}
```

`instType` for perpetuals: `USDT-FUTURES`, `COIN-FUTURES`, `USDC-FUTURES`; spot is `SPOT`.
`instId` is the bare symbol (`BTCUSDT`), the same for spot and USDT futures.

Ack:

```json
{"event":"subscribe","arg":{"instType":"USDT-FUTURES","channel":"trade","instId":"BTCUSDT"}}
```

Unsubscribe uses `"op":"unsubscribe"` and is acked with `"event":"unsubscribe"`.

Errors (`code` arrives as a JSON number live, the docs say string):

```json
{"event":"error","arg":{"instType":"USDT-FUTURES","channel":"books","instId":"NOPEUSDT"},"code":30001,"msg":"instType:USDT-FUTURES,channel:books,instId:NOPEUSDT,precision:null doesn't exist","op":"subscribe"}
{"event":"error","arg":{"instType":"USDT-FUTURES","channel":"bogus","instId":"BTCUSDT"},"code":30016,"msg":"Param error","op":"subscribe"}
{"event":"error","code":30002,"msg":"Unrecognized request:{bad"}
```

## Push envelope

Every data push has the same shape:

```json
{"action":"snapshot"|"update","arg":{"instType":"...","channel":"...","instId":"..."},"data":[...],"ts":1791808984701}
```

The outer `ts` is a JSON number (send time, ms); timestamps inside `data` are strings
(ms since the epoch).

## Trades: `trade`

On subscribe one `snapshot` with recent trades (newest first, up to 50), then `update`
pushes with new trades.

```json
{"action":"snapshot","arg":{"instType":"USDT-FUTURES","channel":"trade","instId":"BTCUSDT"},"data":[{"ts":"1791808977156","price":"82776.4","size":"0.0593","side":"buy","tradeId":"1493520588124995586"},{"ts":"1791808977156","price":"82776.4","size":"0.2308","side":"buy","tradeId":"1493520588124995584"}],"ts":1791808977157}
{"action":"update","arg":{"instType":"USDT-FUTURES","channel":"trade","instId":"BTCUSDT"},"data":[{"ts":"1791808977646","price":"82776.4","size":"0.023","side":"buy","tradeId":"1493520590180204544"}],"ts":1791808977646}
```

`side` is the taker side, `buy` or `sell`. `size` is in base coin.

## Tickers: `ticker`

Every push is a full `snapshot`, roughly every 100 ms.

```json
{"action":"snapshot","arg":{"instType":"USDT-FUTURES","channel":"ticker","instId":"BTCUSDT"},"data":[{"instId":"BTCUSDT","lastPr":"82783.4","bidPr":"82783.3","askPr":"82783.4","bidSz":"1.2888","askSz":"9.1689","open24h":"83079.4","high24h":"84326.4","low24h":"82610","change24h":"-0.00356","fundingRate":"0.0001","nextFundingTime":"1791820800000","markPrice":"82783.4","indexPrice":"82805.9195","holdingAmount":"33502.9652000000073","baseVolume":"23021.0889","quoteVolume":"1925282552.70957","openUtc":"83738.5","symbolType":"1","symbol":"BTCUSDT","ts":"1791808980589"}],"ts":1791808980597}
```

Used for funding: `fundingRate` (per interval), `nextFundingTime` (ms), `markPrice`,
`indexPrice`, `ts`. Spot tickers have no funding fields.

## Depth: `books`, `books1`, `books5`, `books15`

- `books`: full depth. First push `snapshot` (500 levels per side live for BTCUSDT), then
  `update` deltas every ~100 ms. A level with size `"0"` is deleted.
- `books1`, `books5`, `books15`: every push is a `snapshot` of that many levels
  (`books1` pushes on every top-of-book change).
- Asks are sorted ascending, bids descending.

```json
{"action":"snapshot","arg":{"instType":"USDT-FUTURES","channel":"books1","instId":"BTCUSDT"},"data":[{"asks":[["82807","1.0874"]],"bids":[["82806.9","4.1467"]],"ts":"1791808988865","seq":1091175574839,"pseq":0}],"ts":1791808988866}
{"action":"snapshot","arg":{"instType":"USDT-FUTURES","channel":"books","instId":"BTCUSDT"},"data":[{"asks":[["82789","9.1278"],["82789.1","0.0393"]],"bids":[["82788.8","0.4835"],["82788.6","0.03"]],"ts":"1791808998601","seq":1091176375385,"pseq":0}],"ts":1791808998657}
{"action":"update","arg":{"instType":"USDT-FUTURES","channel":"books","instId":"BTCUSDT"},"data":[{"asks":[["82789","9.1278"],["82792.4","0"]],"bids":[["82785.7","0"],["82784.6","0.0023"]],"ts":"1791808998701","seq":1091176380793,"pseq":1091176375385}],"ts":1791808998703}
```

### Sequencing

- `seq` grows with every book change; `pseq` is the `seq` of the previous push on the
  same subscription. A snapshot has `pseq = 0`.
- The first `update` after a snapshot has `pseq` equal to the snapshot's `seq`; every
  later `update` has `pseq` equal to the previous update's `seq`. Anything else is a gap:
  resubscribe (unsubscribe then subscribe), which makes the server send a new snapshot.
- The docs warn that a service restart can reset the sequence; a push with `pseq = 0`
  after a reset is followed by normally ordered pushes. A `snapshot` always resets the
  local book.
- `seq` numbers are JSON numbers (about 1.1e12 live), well inside 63-bit ints.

### Checksum

Older v2 docs described a `checksum` field on `books` pushes: a signed 32-bit CRC32 of
the string formed by interleaving the first 25 bids and asks as
`bid1px:bid1sz:ask1px:ask1sz:bid2px:...` (original strings, one side continuing alone
when the other runs out). On 2026-10-12 the live `books` channel sends no `checksum`
field. The feed verifies it when the field is present and non-zero and resubscribes on a
mismatch; otherwise it relies on `seq`/`pseq`.

## Mapping to market-data streams

| Stream | Channel | Notes |
|---|---|---|
| trades | `trade` | snapshot backlog is emitted too (older `exch_ts`) |
| bbo | `books1` | each push is the full top of book |
| l2 | `books` | snapshot then deltas, `seq`/`pseq` checked |
| funding | `ticker` | emitted when rate, next time, mark or index changes |
