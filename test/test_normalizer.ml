open! Core
open Bitget_feed
module Md = Market_data

let recv_ts = Time_ns.of_int_ns_since_epoch 1_791_809_000_000_000_000

(* Timestamps as ms since the epoch: [Time_ns] sexps depend on the local zone. *)
let ms t = Time_ns.to_int_ns_since_epoch t / 1_000_000

let levels (levels : Md.L2_update.Level.t list) =
  List.map levels ~f:(fun { price; size } ->
    [%sexp (Md.Price.to_string price : string), (Md.Size.to_string size : string)])
;;

let event_sexp : Md.Event.t -> Sexp.t = function
  | Trade t ->
    [%sexp
      Trade
        { instrument = (Md.Instrument.to_string t.instrument : string)
        ; exch_ms = (ms t.exch_ts : int)
        ; price = (Md.Price.to_string t.price : string)
        ; size = (Md.Size.to_string t.size : string)
        ; side = (t.side : Md.Side.t)
        ; trade_id : string = t.trade_id
        }]
  | Bbo b ->
    [%sexp
      Bbo
        { instrument = (Md.Instrument.to_string b.instrument : string)
        ; exch_ms = (ms b.exch_ts : int)
        ; bid =
            ((Md.Price.to_string b.bid_price, Md.Size.to_string b.bid_size)
             : string * string)
        ; ask =
            ((Md.Price.to_string b.ask_price, Md.Size.to_string b.ask_size)
             : string * string)
        }]
  | L2 l ->
    [%sexp
      L2
        { instrument = (Md.Instrument.to_string l.instrument : string)
        ; exch_ms = (ms l.exch_ts : int)
        ; kind = (l.kind : Md.L2_update.Kind.t)
        ; bids = (levels l.bids : Sexp.t list)
        ; asks = (levels l.asks : Sexp.t list)
        }]
  | Funding f ->
    [%sexp
      Funding
        { instrument = (Md.Instrument.to_string f.instrument : string)
        ; exch_ms = (ms f.exch_ts : int)
        ; rate : float = f.rate
        ; next_funding_ms = (ms f.next_funding_time : int)
        ; mark = (Md.Price.to_string f.mark_price : string)
        ; index = (Md.Price.to_string f.index_price : string)
        }]
;;

let feed t frame =
  match Normalizer.frame t ~recv_ts frame with
  | Error error -> print_s [%message "error" (error : Error.t)]
  | Ok { events; resubscribe } ->
    List.iter events ~f:(fun e -> print_s (event_sexp e));
    List.iter resubscribe ~f:(fun arg ->
      print_s [%message "resubscribe" ~arg:(Wire.Arg.to_string arg)])
;;

let%expect_test "trades" =
  let t = Normalizer.create () in
  feed
    t
    {|{"action":"snapshot","arg":{"instType":"USDT-FUTURES","channel":"trade","instId":"BTCUSDT"},"data":[{"ts":"1791808977156","price":"82776.4","size":"0.0593","side":"buy","tradeId":"1493520588124995586"},{"ts":"1791808976000","price":"82770","size":"1.5","side":"sell","tradeId":"1493520588124995584"}],"ts":1791808977157}|};
  feed
    t
    {|{"action":"update","arg":{"instType":"USDT-FUTURES","channel":"trade","instId":"BTCUSDT"},"data":[{"ts":"1791808977646","price":"82776.4","size":"0.023","side":"buy","tradeId":"1493520590180204544"}],"ts":1791808977646}|};
  [%expect
    {|
    (Trade
     ((instrument bitget:BTCUSDT) (exch_ms 1791808976000) (price 82770)
      (size 1.5) (side Sell) (trade_id 1493520588124995584)))
    (Trade
     ((instrument bitget:BTCUSDT) (exch_ms 1791808977156) (price 82776.4)
      (size 0.0593) (side Buy) (trade_id 1493520588124995586)))
    (Trade
     ((instrument bitget:BTCUSDT) (exch_ms 1791808977646) (price 82776.4)
      (size 0.023) (side Buy) (trade_id 1493520590180204544)))
    |}]
;;

let%expect_test "books1 gives bbo" =
  let t = Normalizer.create () in
  feed
    t
    {|{"action":"snapshot","arg":{"instType":"USDT-FUTURES","channel":"books1","instId":"BTCUSDT"},"data":[{"asks":[["82807","1.0874"]],"bids":[["82806.9","4.1467"]],"ts":"1791808988865","seq":1091175574839,"pseq":0}],"ts":1791808988866}|};
  (* one side empty: nothing *)
  feed
    t
    {|{"action":"snapshot","arg":{"instType":"USDT-FUTURES","channel":"books1","instId":"BTCUSDT"},"data":[{"asks":[],"bids":[["82806.9","4.1467"]],"ts":"1791808988870","seq":1091175575227,"pseq":0}],"ts":1791808988871}|};
  [%expect
    {|
    (Bbo
     ((instrument bitget:BTCUSDT) (exch_ms 1791808988865) (bid (82806.9 4.1467))
      (ask (82807 1.0874))))
    |}]
;;

let ticker ~rate ~mark ~ts =
  sprintf
    {|{"action":"snapshot","arg":{"instType":"USDT-FUTURES","channel":"ticker","instId":"BTCUSDT"},"data":[{"instId":"BTCUSDT","lastPr":"82783.4","bidPr":"82783.3","askPr":"82783.4","bidSz":"1.2888","askSz":"9.1689","fundingRate":"%s","nextFundingTime":"1791820800000","markPrice":"%s","indexPrice":"82805.9195","holdingAmount":"33502.9652000000073","symbolType":"1","symbol":"BTCUSDT","ts":"%d"}],"ts":%d}|}
    rate
    mark
    ts
    (ts + 8)
;;

let%expect_test "ticker gives funding only on change" =
  let t = Normalizer.create () in
  feed t (ticker ~rate:"0.0001" ~mark:"82783.4" ~ts:1791808980589);
  feed t (ticker ~rate:"0.0001" ~mark:"82783.4" ~ts:1791808980693);
  feed t (ticker ~rate:"0.0001" ~mark:"82790.1" ~ts:1791808980793);
  feed t (ticker ~rate:"-0.00005" ~mark:"82790.1" ~ts:1791808980893);
  [%expect
    {|
    (Funding
     ((instrument bitget:BTCUSDT) (exch_ms 1791808980589) (rate 0.0001)
      (next_funding_ms 1791820800000) (mark 82783.4) (index 82805.9195)))
    (Funding
     ((instrument bitget:BTCUSDT) (exch_ms 1791808980793) (rate 0.0001)
      (next_funding_ms 1791820800000) (mark 82790.1) (index 82805.9195)))
    (Funding
     ((instrument bitget:BTCUSDT) (exch_ms 1791808980893) (rate -5E-05)
      (next_funding_ms 1791820800000) (mark 82790.1) (index 82805.9195)))
    |}]
;;

let%expect_test "spot ticker without funding fields gives nothing" =
  let t = Normalizer.create () in
  feed
    t
    {|{"action":"snapshot","arg":{"instType":"SPOT","channel":"ticker","instId":"BTCUSDT"},"data":[{"instId":"BTCUSDT","lastPr":"82783.4","bidPr":"82783.3","askPr":"82783.4","bidSz":"1","askSz":"2","ts":"1791808980589"}],"ts":1791808980597}|};
  [%expect {| |}]
;;

let books ?checksum ~action ~bids ~asks ~seq ~pseq () =
  let side levels =
    String.concat
      ~sep:","
      (List.map levels ~f:(fun (px, sz) -> sprintf {|["%s","%s"]|} px sz))
  in
  let checksum =
    Option.value_map checksum ~default:"" ~f:(fun c -> sprintf {|,"checksum":%d|} c)
  in
  sprintf
    {|{"action":"%s","arg":{"instType":"USDT-FUTURES","channel":"books","instId":"BTCUSDT"},"data":[{"asks":[%s],"bids":[%s],"ts":"%d","seq":%d,"pseq":%d%s}],"ts":%d}|}
    action
    (side asks)
    (side bids)
    (1791808998000 + seq)
    seq
    pseq
    checksum
    (1791808998001 + seq)
;;

let%expect_test "books: update before snapshot, snapshot, deltas, gap, resync" =
  let t = Normalizer.create () in
  print_endline "-- update before any snapshot is dropped";
  feed t (books ~action:"update" ~bids:[ "99", "1" ] ~asks:[] ~seq:5 ~pseq:4 ());
  print_endline "-- snapshot";
  feed
    t
    (books
       ~action:"snapshot"
       ~bids:[ "100", "1"; "99.5", "2" ]
       ~asks:[ "100.5", "3"; "101", "4" ]
       ~seq:10
       ~pseq:0
       ());
  print_endline "-- delta continuing seq";
  feed
    t
    (books
       ~action:"update"
       ~bids:[ "100", "0"; "99.8", "5" ]
       ~asks:[]
       ~seq:12
       ~pseq:10
       ());
  print_endline "-- gap: pseq 13 after seq 12";
  feed t (books ~action:"update" ~bids:[] ~asks:[ "100.5", "0" ] ~seq:15 ~pseq:13 ());
  print_endline "-- later update while out of sync is dropped";
  feed t (books ~action:"update" ~bids:[] ~asks:[ "100.5", "1" ] ~seq:16 ~pseq:15 ());
  print_endline "-- fresh snapshot after resubscribe";
  feed
    t
    (books
       ~action:"snapshot"
       ~bids:[ "99.8", "5" ]
       ~asks:[ "101", "4" ]
       ~seq:20
       ~pseq:0
       ());
  feed t (books ~action:"update" ~bids:[ "99.9", "1" ] ~asks:[] ~seq:21 ~pseq:20 ());
  [%expect
    {|
    -- update before any snapshot is dropped
    -- snapshot
    (L2
     ((instrument bitget:BTCUSDT) (exch_ms 1791808998010) (kind Snapshot)
      (bids ((100 1) (99.5 2))) (asks ((100.5 3) (101 4)))))
    -- delta continuing seq
    (L2
     ((instrument bitget:BTCUSDT) (exch_ms 1791808998012) (kind Delta)
      (bids ((100 0) (99.8 5))) (asks ())))
    -- gap: pseq 13 after seq 12
    (resubscribe (arg USDT-FUTURES/books/BTCUSDT))
    -- later update while out of sync is dropped
    -- fresh snapshot after resubscribe
    (L2
     ((instrument bitget:BTCUSDT) (exch_ms 1791808998020) (kind Snapshot)
      (bids ((99.8 5))) (asks ((101 4)))))
    (L2
     ((instrument bitget:BTCUSDT) (exch_ms 1791808998021) (kind Delta)
      (bids ((99.9 1))) (asks ())))
    |}]
;;

let%expect_test "books: checksum verified when present" =
  let t = Normalizer.create () in
  let bids = [ "100", "1" ]
  and asks = [ "100.5", "3" ] in
  let good = Checksum.compute ~bids ~asks () in
  feed t (books ~action:"snapshot" ~bids ~asks ~seq:1 ~pseq:0 ~checksum:good ());
  let after = Checksum.compute ~bids:[ "100", "2" ] ~asks () in
  feed
    t
    (books
       ~action:"update"
       ~bids:[ "100", "2" ]
       ~asks:[]
       ~seq:2
       ~pseq:1
       ~checksum:after
       ());
  print_endline "-- wrong checksum";
  feed
    t
    (books ~action:"update" ~bids:[ "100", "3" ] ~asks:[] ~seq:3 ~pseq:2 ~checksum:42 ());
  print_endline "-- zero means absent";
  feed t (books ~action:"snapshot" ~bids ~asks ~seq:4 ~pseq:0 ~checksum:0 ());
  [%expect
    {|
    (L2
     ((instrument bitget:BTCUSDT) (exch_ms 1791808998001) (kind Snapshot)
      (bids ((100 1))) (asks ((100.5 3)))))
    (L2
     ((instrument bitget:BTCUSDT) (exch_ms 1791808998002) (kind Delta)
      (bids ((100 2))) (asks ())))
    -- wrong checksum
    (resubscribe (arg USDT-FUTURES/books/BTCUSDT))
    -- zero means absent
    (L2
     ((instrument bitget:BTCUSDT) (exch_ms 1791808998004) (kind Snapshot)
      (bids ((100 1))) (asks ((100.5 3)))))
    |}]
;;

let%expect_test "books: one book per subscription" =
  let t = Normalizer.create () in
  let eth frame =
    String.substr_replace_all
      frame
      ~pattern:{|"instId":"BTCUSDT"|}
      ~with_:{|"instId":"ETHUSDT"|}
  in
  feed t (books ~action:"snapshot" ~bids:[ "100", "1" ] ~asks:[] ~seq:10 ~pseq:0 ());
  feed t (eth (books ~action:"snapshot" ~bids:[ "3", "1" ] ~asks:[] ~seq:50 ~pseq:0 ()));
  feed t (books ~action:"update" ~bids:[ "100", "2" ] ~asks:[] ~seq:11 ~pseq:10 ());
  feed t (eth (books ~action:"update" ~bids:[ "3", "2" ] ~asks:[] ~seq:51 ~pseq:50 ()));
  [%expect
    {|
    (L2
     ((instrument bitget:BTCUSDT) (exch_ms 1791808998010) (kind Snapshot)
      (bids ((100 1))) (asks ())))
    (L2
     ((instrument bitget:ETHUSDT) (exch_ms 1791808998050) (kind Snapshot)
      (bids ((3 1))) (asks ())))
    (L2
     ((instrument bitget:BTCUSDT) (exch_ms 1791808998011) (kind Delta)
      (bids ((100 2))) (asks ())))
    (L2
     ((instrument bitget:ETHUSDT) (exch_ms 1791808998051) (kind Delta)
      (bids ((3 2))) (asks ())))
    |}]
;;

(* Only whether it failed: ppx_yojson_conv errors embed source paths. *)
let feed_result t frame =
  match Normalizer.frame t ~recv_ts frame with
  | Error _ -> print_endline "error"
  | Ok output -> print_s [%sexp (output : Normalizer.Output.t)]
;;

let%expect_test "bad frames and events" =
  let t = Normalizer.create () in
  feed_result t "pong";
  feed_result
    t
    {|{"event":"subscribe","arg":{"instType":"USDT-FUTURES","channel":"trade","instId":"BTCUSDT"}}|};
  feed
    t
    {|{"event":"error","arg":{"instType":"USDT-FUTURES","channel":"books","instId":"NOPEUSDT"},"code":30001,"msg":"doesn't exist","op":"subscribe"}|};
  feed_result t "garbage";
  (* missing fields in a trade *)
  feed_result
    t
    {|{"action":"update","arg":{"instType":"USDT-FUTURES","channel":"trade","instId":"BTCUSDT"},"data":[{"ts":"1","price":"1"}],"ts":1}|};
  (* unparsable price *)
  feed_result
    t
    {|{"action":"update","arg":{"instType":"USDT-FUTURES","channel":"trade","instId":"BTCUSDT"},"data":[{"ts":"1","price":"abc","size":"1","side":"buy","tradeId":"7"}],"ts":1}|};
  (* unknown side *)
  feed_result
    t
    {|{"action":"update","arg":{"instType":"USDT-FUTURES","channel":"trade","instId":"BTCUSDT"},"data":[{"ts":"1","price":"1","size":"1","side":"long","tradeId":"7"}],"ts":1}|};
  (* channels this feed does not read are ignored *)
  feed_result
    t
    {|{"action":"snapshot","arg":{"instType":"USDT-FUTURES","channel":"candle1m","instId":"BTCUSDT"},"data":[["1","2"]],"ts":1}|};
  print_endline "-- a bad frame does not break the stream";
  feed
    t
    {|{"action":"update","arg":{"instType":"USDT-FUTURES","channel":"trade","instId":"BTCUSDT"},"data":[{"ts":"1791808977646","price":"82776.4","size":"0.023","side":"sell","tradeId":"9"}],"ts":1791808977646}|};
  [%expect
    {|
    ((events ()) (resubscribe ()))
    ((events ()) (resubscribe ()))
    (error
     (error
      ("bitget error event" (arg (USDT-FUTURES/books/NOPEUSDT)) (code (30001))
       (msg ("doesn't exist")))))
    error
    error
    error
    error
    ((events ()) (resubscribe ()))
    -- a bad frame does not break the stream
    (Trade
     ((instrument bitget:BTCUSDT) (exch_ms 1791808977646) (price 82776.4)
      (size 0.023) (side Sell) (trade_id 9)))
    |}]
;;
