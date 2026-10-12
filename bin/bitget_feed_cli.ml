open! Core
open Async
module Md = Market_data

let streams_arg =
  Command.Arg_type.create (fun s ->
    String.split s ~on:','
    |> List.filter ~f:(Fn.non String.is_empty)
    |> List.map ~f:Md.Stream.of_string)
;;

let print_events (feed : Md.Feed.t) ~streams ~count =
  let module F = (val feed) in
  let printed = ref 0 in
  let done_ = Ivar.create () in
  let print event =
    if Option.for_all count ~f:(fun n -> !printed < n)
    then (
      incr printed;
      print_s [%sexp (event : Md.Event.t)]);
    if Option.exists count ~f:(fun n -> !printed >= n) then Ivar.fill_if_empty done_ ()
  in
  let drain pipe ~f = Pipe.iter_without_pushback pipe ~f:(fun x -> print (f x)) in
  let readers =
    List.map streams ~f:(fun (stream : Md.Stream.t) ->
      match stream with
      | Trades -> drain F.trades ~f:(fun x -> Md.Event.Trade x)
      | Bbo -> drain F.bbo ~f:(fun x -> Md.Event.Bbo x)
      | L2 -> drain F.l2 ~f:(fun x -> Md.Event.L2 x)
      | Funding -> drain F.funding ~f:(fun x -> Md.Event.Funding x)
      | Private -> return ())
  in
  Deferred.any [ Ivar.read done_; Deferred.all_unit readers ]
;;

let feed_command =
  Command.async
    ~summary:"Print normalized public market data from Bitget"
    (let%map_open.Command symbols =
       flag
         "-symbol"
         (one_or_more_as_list string)
         ~doc:"SYM venue symbol, e.g. BTCUSDT (repeatable)"
     and streams =
       flag
         "-streams"
         (optional_with_default [ Md.Stream.Trades; Bbo; L2; Funding ] streams_arg)
         ~doc:"LIST comma separated: trades,bbo,l2,funding (default all)"
     and count = flag "-count" (optional int) ~doc:"N stop after N events"
     and seconds = flag "-seconds" (optional float) ~doc:"S stop after S seconds"
     and inst_type =
       flag
         "-inst-type"
         (optional_with_default Bitget_feed.Config.default_inst_type string)
         ~doc:"TYPE USDT-FUTURES (default), COIN-FUTURES, USDC-FUTURES or SPOT"
     and url =
       flag "-url" (optional string) ~doc:"URL websocket endpoint (default mainnet)"
     and raw = flag "-raw" no_arg ~doc:" also print raw frames to stderr" in
     fun () ->
       let config =
         Bitget_feed.Config.create ?url:(Option.map url ~f:Uri.of_string) ~inst_type ()
       in
       let on_raw =
         Option.some_if raw (fun ~stream ~recv_ts:_ frame ->
           Core.eprintf "%s %s\n%!" (Md.Stream.to_string stream) frame)
       in
       let%bind feed = Bitget_feed.Live_feed.create ?on_raw config ~symbols ~streams in
       let timeout =
         match seconds with
         | None -> Deferred.never ()
         | Some s -> after (Time_float.Span.of_sec s)
       in
       let%bind () = Deferred.any [ print_events feed ~streams ~count; timeout ] in
       let module F = (val feed) in
       F.close ())
;;

let () =
  Command_unix.run
    (Command.group
       ~summary:"Bitget public market data (read-only, no credentials)"
       [ "feed", feed_command ])
;;
