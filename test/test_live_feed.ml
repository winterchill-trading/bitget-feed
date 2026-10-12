(* [Live_feed] against a loopback Bitget-like server: stats on malformed frames, error
   events and reconnects. *)

open! Core
open Async
open Bitget_feed
module Server = Loopback_server

let wait_until f =
  let deadline = Time_ns.add (Time_ns.now ()) (Time_ns.Span.of_sec 5.) in
  Deferred.repeat_until_finished () (fun () ->
    if f ()
    then return (`Finished true)
    else if Time_ns.( > ) (Time_ns.now ()) deadline
    then return (`Finished false)
    else Clock_ns.after (Time_ns.Span.of_int_ms 1) >>| fun () -> `Repeat ())
;;

let trade ~(arg : Wire.Arg.t) ~id =
  sprintf
    {|{"action":"update","arg":{"instType":"%s","channel":"trade","instId":"%s"},"data":[{"ts":"1791808977646","price":"82776.4","size":"0.023","side":"buy","tradeId":"%d"}],"ts":1791808977646}|}
    arg.inst_type
    arg.inst_id
    id
;;

let greeting =
  [ "garbage"
  ; {|{"action":"update","arg":{"instType":"USDT-FUTURES","channel":"trade","instId":"BTCUSDT"},"data":[{"ts":"x","price":"1","size":"1","side":"buy","tradeId":"1"}]}|}
  ; {|{"event":"error","code":30001,"msg":"instType:USDT-FUTURES,channel:trade,instId:NOPE doesn't exist"}|}
  ]
;;

let%expect_test "stats count parse errors, error events and reconnects" =
  Log.Global.set_output [];
  let on_subscribe ~connection arg = [ trade ~arg ~id:connection ] in
  let%bind server = Server.start ~greeting ~on_subscribe () in
  let%bind (module Feed : Market_data.Feed.S), stats =
    Live_feed.create_with_stats
      (Config.create ~url:(Server.url server) ())
      ~symbols:[ "BTCUSDT" ]
      ~streams:[ Trades ]
  in
  let%bind (_ : bool) = wait_until (fun () -> (stats ()).frames = 5) in
  print_s [%sexp (stats () : Live_feed.Stats.t)];
  let%bind () = Server.drop server 0 in
  let%bind (_ : bool) = wait_until (fun () -> (stats ()).frames = 7) in
  print_s [%sexp (stats () : Live_feed.Stats.t)];
  let%bind () = Feed.close () in
  let%bind trades = Pipe.to_list Feed.trades in
  print_s [%sexp (List.map trades ~f:(fun t -> t.trade_id) : string list)];
  [%expect
    {|
    ((frames 5) (parse_errors 2) (error_events 1) (reconnects 0))
    ((frames 7) (parse_errors 2) (error_events 1) (reconnects 1))
    (1 2)
    |}];
  Server.close server
;;
