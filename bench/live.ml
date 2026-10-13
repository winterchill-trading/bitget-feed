(* Frames per second and words per frame through [Live_feed], end to end: the recorded
   trades minute (test/fixtures), repeated, is written as pre-encoded websocket frames by
   the in-process loopback server in one burst, and the feed's trades pipe is drained a
   batch at a time. Words are minor heap words over the whole receive phase (socket reads,
   framing, the delivery from [Ws_client], [Normalizer.frame] and the pipe writes),
   divided by the number of frames. [via messages] is the delivery before [on_message]
   (reading [Ws_client.messages] one frame at a time). *)

open! Core
open Async
open Bitget_feed
module Server = Bitget_feed_test.Loopback_server

let repeats = 100
let runs = 10

let frames =
  String.split_lines Frames.trades
  |> List.filter_map ~f:(fun line -> Option.map (String.lsplit2 line ~on:' ') ~f:snd)
;;

let burst =
  String.concat
    (List.concat
       (List.init repeats ~f:(fun _ -> List.map frames ~f:Server.encode_text_frame)))
;;

let n = repeats * List.length frames

let measure name start =
  let%bind server = Server.start () in
  let seen = ref 0 in
  let done_ = ref (Ivar.create ()) in
  let target = ref 1 in
  let on_raw ~stream:_ ~recv_ts:_ _ =
    incr seen;
    if !seen = !target then Ivar.fill_exn !done_ ()
  in
  let%bind live =
    start
      ~on_raw
      (Config.create ~url:(Server.url server) ())
      ~symbols:[ "BTCUSDT" ]
      ~streams:[ Market_data.Stream.Trades ]
  in
  let module F = (val Live_feed.feed live : Market_data.Feed.S) in
  don't_wait_for (Pipe.iter' F.trades ~f:(fun (_ : _ Queue.t) -> return ()));
  (* The server acknowledges the subscription with one frame; let it through first. *)
  let%bind () = Ivar.read !done_ in
  let run () =
    seen := 0;
    target := n;
    done_ := Ivar.create ();
    Gc.full_major ();
    let words0 = Gc.minor_words () in
    let t0 = Time_ns.now () in
    Server.write_raw server burst;
    let%map () = Ivar.read !done_ in
    let t1 = Time_ns.now () in
    ( Time_ns.Span.to_sec (Time_ns.diff t1 t0)
    , Float.of_int (Gc.minor_words () - words0) /. Float.of_int n )
  in
  (* One warm-up run. *)
  let%bind (_ : float * float) = run () in
  let%bind results = Deferred.List.init runs ~how:`Sequential ~f:(fun _ -> run ()) in
  let best =
    List.fold results ~init:Float.infinity ~f:(fun acc (s, _) -> Float.min acc s)
  in
  let words = List.map results ~f:snd in
  printf
    "%-12s %8.0f ns/frame  %6.1f words/frame (min %.1f max %.1f)\n%!"
    name
    (best *. 1e9 /. Float.of_int n)
    (List.sum (module Float) words ~f:Fn.id /. Float.of_int runs)
    (Option.value_exn (List.min_elt words ~compare:Float.compare))
    (Option.value_exn (List.max_elt words ~compare:Float.compare));
  let%bind () = F.close () in
  Server.close server
;;

let main () =
  Log.Global.set_output [];
  printf "trades: %d frames per run, one burst, best of %d runs\n%!" n runs;
  let%bind () =
    measure "via messages" (fun ~on_raw config ->
      Live_feed.For_testing.connect_via_messages ~on_raw config)
  in
  measure "on_message" (fun ~on_raw config -> Live_feed.connect ~on_raw config)
;;

let () =
  Command_unix.run
    (Command.async
       ~summary:"Live_feed frames/s against a local server"
       (Command.Param.return main))
;;
