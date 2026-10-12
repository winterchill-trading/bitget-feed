(* [Live_feed] reconnection stepped with a synthetic clock: the reconnect delay only
   elapses when the test advances the clock, and [recv_ts] comes from the same clock.
   Socket I/O still runs in real time. *)

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

(* The delay of the next alarm on [clock] if it is shorter than the 30s keepalive: the
   reconnect sleep. *)
let reconnect_sleep clock =
  match Time_source.next_alarm_fires_at clock with
  | None -> None
  | Some at ->
    let delay = Time_ns.diff at (Time_source.now clock) in
    Option.some_if Time_ns.Span.(delay < of_sec 30.) delay
;;

(* Lets real I/O that should NOT happen have a chance to happen. *)
let settle () = Clock_ns.after (Time_ns.Span.of_int_ms 50)

let trade ~(arg : Wire.Arg.t) ~id =
  sprintf
    {|{"action":"update","arg":{"instType":"%s","channel":"trade","instId":"%s"},"data":[{"ts":"1791808977646","price":"82776.4","size":"0.023","side":"buy","tradeId":"%d"}],"ts":1791808977646}|}
    arg.inst_type
    arg.inst_id
    id
;;

let%expect_test "reconnect waits for the backoff on the synthetic clock" =
  Log.Global.set_output [];
  let on_subscribe ~connection arg = [ trade ~arg ~id:connection ] in
  let%bind server = Server.start ~on_subscribe () in
  let clock = Time_source.create ~now:Time_ns.epoch () in
  let%bind (module Feed : Market_data.Feed.S), stats =
    Live_feed.create_with_stats
      ~time_source:(Time_source.read_only clock)
      (Config.create ~url:(Server.url server) ())
      ~symbols:[ "BTCUSDT" ]
      ~streams:[ Trades ]
  in
  let%bind first = Pipe.read Feed.trades in
  let%bind () = Server.drop server 0 in
  let%bind (_ : bool) = wait_until (fun () -> Option.is_some (reconnect_sleep clock)) in
  let sleep = Option.value_exn (reconnect_sleep clock) in
  (* The venue-net default backoff is 0.5s with 20% jitter. *)
  let sleep_ms = Float.iround_nearest_exn (Time_ns.Span.to_ms sleep) in
  print_s
    [%message "" ~sleep_within_400_600ms:(sleep_ms >= 400 && sleep_ms <= 600 : bool)];
  let%bind () =
    Time_source.advance_by_alarms_by clock Time_ns.Span.(sleep - of_int_ms 10)
  in
  let%bind () = settle () in
  print_s
    [%message
      "just before the backoff"
        ~connections:(Queue.length server.sockets : int)
        ~reconnects:((stats ()).reconnects : int)];
  let%bind () = Time_source.advance_by_alarms_by clock (Time_ns.Span.of_int_ms 10) in
  let%bind (_ : bool) = wait_until (fun () -> (stats ()).reconnects = 1) in
  let%bind second = Pipe.read Feed.trades in
  let recv_ts : [ `Eof | `Ok of Market_data.Trade.t ] -> Time_ns.t option = function
    | `Eof -> None
    | `Ok t -> Some t.recv_ts
  in
  print_s
    [%message
      "after the backoff"
        ~connections:(Queue.length server.sockets : int)
        ~stats:(stats () : Live_feed.Stats.t)
        ~first_recv_is_epoch:
          ([%equal: Time_ns.t option] (recv_ts first) (Some Time_ns.epoch) : bool)
        ~second_recv_is_epoch_plus_sleep:
          ([%equal: Time_ns.t option]
             (recv_ts second)
             (Some (Time_ns.add Time_ns.epoch sleep))
           : bool)];
  [%expect
    {|
    (sleep_within_400_600ms true)
    ("just before the backoff" (connections 1) (reconnects 0))
    ("after the backoff" (connections 2)
     (stats ((frames 4) (parse_errors 0) (error_events 0) (reconnects 1)))
     (first_recv_is_epoch true) (second_recv_is_epoch_plus_sleep true))
    |}];
  let%bind () = Feed.close () in
  Server.close server
;;
