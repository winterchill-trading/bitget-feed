(* [Live_feed.feed_with_gaps] on a synthetic clock: a book sequence break reports a gap
   for its instrument, a reconnect reports one for the whole connection, each before the
   first frame that follows it. *)

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

(* The reconnect sleep: the next alarm, if it is shorter than the 30s keepalive. *)
let reconnect_sleep clock =
  match Time_source.next_alarm_fires_at clock with
  | None -> None
  | Some at ->
    let delay = Time_ns.diff at (Time_source.now clock) in
    Option.some_if Time_ns.Span.(delay < of_sec 30.) delay
;;

let trade ~(arg : Wire.Arg.t) ~id =
  sprintf
    {|{"action":"update","arg":{"instType":"%s","channel":"trade","instId":"%s"},"data":[{"ts":"1791808977646","price":"82776.4","size":"0.023","side":"buy","tradeId":"%d"}],"ts":1791808977646}|}
    arg.inst_type
    arg.inst_id
    id
;;

let books ~action ~bid ~seq ~pseq =
  sprintf
    {|{"action":"%s","arg":{"instType":"USDT-FUTURES","channel":"books","instId":"BTCUSDT"},"data":[{"asks":[["101","1"]],"bids":[["%s","1"]],"ts":"1791808998000","seq":%d,"pseq":%d}],"ts":1791808998001}|}
    action
    bid
    seq
    pseq
;;

let%expect_test "gaps on a book resync and on a reconnect" =
  Log.Global.set_output [];
  let books_subscriptions = ref 0 in
  let on_subscribe ~connection (arg : Wire.Arg.t) =
    match arg.channel with
    | "books" ->
      incr books_subscriptions;
      (match !books_subscriptions with
       | 1 ->
         [ books ~action:"snapshot" ~bid:"99" ~seq:10 ~pseq:0
         ; books ~action:"update" ~bid:"99.5" ~seq:12 ~pseq:10
         ; (* pseq 13 after seq 12: the book is out of sync *)
           books ~action:"update" ~bid:"99.6" ~seq:15 ~pseq:13
         ]
       | _ -> [ books ~action:"snapshot" ~bid:"98" ~seq:20 ~pseq:0 ])
    | _ -> [ trade ~arg ~id:connection ]
  in
  let%bind server = Server.start ~on_subscribe () in
  let clock = Time_source.create ~now:Time_ns.epoch () in
  let since_epoch ts = Time_ns.diff ts Time_ns.epoch in
  let gaps_before = ref (fun () -> 0) in
  (* For each frame carrying data, how many gaps were already written when it arrived. *)
  let arrivals = Queue.create () in
  let on_raw ~stream ~recv_ts:_ frame =
    if String.is_substring frame ~substring:{|"data"|}
    then Queue.enqueue arrivals (stream, !gaps_before ())
  in
  let%bind t =
    Live_feed.connect
      ~on_raw
      ~time_source:(Time_source.read_only clock)
      (Config.create ~url:(Server.url server) ())
      ~symbols:[ "BTCUSDT" ]
      ~streams:[ Trades; L2 ]
  in
  let (module Feed : Market_data.Feed.With_gaps.S) = Live_feed.feed_with_gaps t in
  (gaps_before := fun () -> Pipe.length Feed.gaps);
  let%bind (_ : _) = Pipe.read Feed.trades in
  (* snapshot, delta, then the snapshot sent again after the resubscribe *)
  let%bind l2 = Pipe.read_exactly Feed.l2 ~num_values:3 in
  let l2 =
    match l2 with
    | `Exactly q -> Queue.to_list q
    | `Eof | `Fewer _ -> []
  in
  print_s
    [%message
      "after the resync"
        ~l2_kinds:(List.map l2 ~f:(fun u -> u.kind) : Market_data.L2_update.Kind.t list)];
  let%bind () = Server.drop server 0 in
  let%bind (_ : bool) = wait_until (fun () -> Option.is_some (reconnect_sleep clock)) in
  let sleep = Option.value_exn (reconnect_sleep clock) in
  let%bind () = Time_source.advance_by_alarms_by clock sleep in
  let%bind (_ : _) = Pipe.read Feed.trades in
  let gaps =
    match Pipe.read_now' Feed.gaps with
    | `Ok q -> Queue.to_list q
    | `Eof | `Nothing_available -> []
  in
  List.iter gaps ~f:(fun (gap : Market_data.Gap.t) ->
    print_s
      [%message
        ""
          ~at:
            (if Time_ns.Span.equal (since_epoch gap.recv_ts) sleep
             then "epoch + backoff"
             else Time_ns.Span.to_string (since_epoch gap.recv_ts))
          ~venue:(gap.venue : Market_data.Venue.t)
          ~instrument:(gap.instrument : Market_data.Instrument.t option)
          ~stream:(gap.stream : Market_data.Stream.t option)
          ~reason:(gap.reason : Market_data.Gap.Reason.t)]);
  print_s
    [%message
      "gaps already written when each data frame arrived"
        ~_:(Queue.to_list arrivals : (Market_data.Stream.t * int) list)];
  print_s [%message "" ~reconnects:((Live_feed.stats t).reconnects : int)];
  [%expect
    {|
    ("after the resync" (l2_kinds (Snapshot Delta Snapshot)))
    ((at 0s) (venue Bitget) (instrument (((venue Bitget) (symbol BTCUSDT))))
     (stream (L2)) (reason Resync))
    ((at "epoch + backoff") (venue Bitget) (instrument ()) (stream (Trades))
     (reason Resync))
    ("gaps already written when each data frame arrived"
     ((Trades 0) (L2 0) (L2 0) (L2 0) (L2 1) (Trades 2)))
    (reconnects 1)
    |}];
  let%bind () = Feed.close () in
  Server.close server
;;
