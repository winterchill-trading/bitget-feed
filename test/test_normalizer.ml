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
     ((instrument bitget:BTCUSDT) (exch_ms 1791808977156) (price 82776.4)
      (size 0.0593) (side Buy) (trade_id 1493520588124995586)))
    (Trade
     ((instrument bitget:BTCUSDT) (exch_ms 1791808976000) (price 82770)
      (size 1.5) (side Sell) (trade_id 1493520588124995584)))
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
