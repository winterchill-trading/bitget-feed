open! Core
open Async
module Md = Market_data
module Ws_client = Venue_net.Ws_client

let arg (config : Config.t) stream symbol : Wire.Arg.t =
  { inst_type = config.inst_type; channel = Normalizer.channel stream; inst_id = symbol }
;;

let ping : Ws_client.Ping.t = `Text (Wire.ping, Time_ns.Span.of_int_sec 30)

module Stats = struct
  type t =
    { frames : int
    ; parse_errors : int
    ; error_events : int
    ; reconnects : int
    }
  [@@deriving sexp_of]
end

type t =
  { feed : Md.Feed.With_gaps.t
  ; stats : unit -> Stats.t
  }

let feed t = Md.Feed.With_gaps.to_feed t.feed
let feed_with_gaps t = t.feed
let stats t = t.stats ()

let connect ?on_raw ?time_source config ~symbols ~streams =
  let now () =
    match time_source with
    | None -> Time_ns.now ()
    | Some time_source -> Time_source.now time_source
  in
  let streams = List.dedup_and_sort streams ~compare:Md.Stream.compare in
  if List.mem streams Private ~equal:Md.Stream.equal
  then
    raise_s [%message "Bitget Live_feed.create: the private stream is not a market feed"];
  let trades_r, trades_w = Pipe.create () in
  let bbo_r, bbo_w = Pipe.create () in
  let l2_r, l2_w = Pipe.create () in
  let funding_r, funding_w = Pipe.create () in
  let gaps_r, gaps_w = Pipe.create () in
  let gap ~recv_ts ~stream ?instrument () =
    Pipe.write_without_pushback_if_open
      gaps_w
      { Md.Gap.recv_ts
      ; venue = Bitget
      ; instrument
      ; stream = Some stream
      ; reason = Resync
      }
  in
  let emit : Md.Event.t -> unit = function
    | Trade x -> Pipe.write_without_pushback_if_open trades_w x
    | Bbo x -> Pipe.write_without_pushback_if_open bbo_w x
    | L2 x -> Pipe.write_without_pushback_if_open l2_w x
    | Funding x -> Pipe.write_without_pushback_if_open funding_w x
  in
  let normalizer = Normalizer.create () in
  let frames = ref 0 in
  let parse_errors = ref 0 in
  let error_events = ref 0 in
  let connect stream =
    let args = List.map symbols ~f:(arg config stream) in
    let stream_name = Md.Stream.to_string stream in
    (* Reconnects already reported as a gap. [on_connect] normally runs before any frame
       of the new connection is handled, but whichever of the two sees a new reconnect
       first reports it, so the gap always precedes the new connection's events. *)
    let reported = ref 0 in
    let report_reconnect ws =
      let reconnects = Ws_client.reconnects ws in
      if reconnects > !reported
      then (
        reported := reconnects;
        gap ~recv_ts:(now ()) ~stream ())
    in
    let on_connect ws =
      report_reconnect ws;
      if Ws_client.reconnects ws > 0
      then Log.Global.info "bitget live feed: %s reconnected" stream_name;
      Ws_client.send ws (Wire.subscribe args)
    in
    let%map ws =
      Ws_client.connect
        ~ping
        ~on_connect
        ~log_name:("bitget " ^ stream_name)
        ?time_source
        ~url:config.url
        ()
      >>| Or_error.ok_exn
    in
    let resubscribe arg =
      let%bind () = Ws_client.send ws (Wire.unsubscribe [ arg ]) in
      Ws_client.send ws (Wire.subscribe [ arg ])
    in
    let handle frame =
      report_reconnect ws;
      let recv_ts = now () in
      incr frames;
      Option.iter on_raw ~f:(fun on_raw -> on_raw ~stream ~recv_ts frame);
      let output =
        match Wire.decode frame with
        | Error _ as error ->
          incr parse_errors;
          error
        | Ok message ->
          let output = Normalizer.message normalizer ~recv_ts message in
          (match message, output with
           | Event _, Error _ -> incr error_events
           | _, Error _ -> incr parse_errors
           | _, Ok _ -> ());
          output
      in
      match output with
      | Error error ->
        Log.Global.error_s
          [%message
            "bitget live feed: skipped frame"
              ~stream:stream_name
              ~frame:(String.prefix frame 500 : string)
              (error : Error.t)]
      | Ok { events; resubscribe = args } ->
        List.iter events ~f:emit;
        List.iter args ~f:(fun (arg : Wire.Arg.t) ->
          gap ~recv_ts ~stream ~instrument:(Normalizer.instrument arg.inst_id) ();
          don't_wait_for (resubscribe arg))
    in
    don't_wait_for (Pipe.iter_without_pushback (Ws_client.messages ws) ~f:handle);
    ws
  in
  let opened = ref [] in
  let close_all () = Deferred.List.iter !opened ~how:`Parallel ~f:Ws_client.close in
  let%bind () =
    match%bind
      Monitor.try_with (fun () ->
        Deferred.List.iter streams ~how:`Sequential ~f:(fun stream ->
          let%map ws = connect stream in
          opened := ws :: !opened))
    with
    | Ok () -> return ()
    | Error exn ->
      let%map () = close_all () in
      raise exn
  in
  let closed =
    Lazy_deferred.create (fun () ->
      let%map () = close_all () in
      Pipe.close trades_w;
      Pipe.close bbo_w;
      Pipe.close l2_w;
      Pipe.close funding_w;
      Pipe.close gaps_w)
  in
  let stats () : Stats.t =
    { frames = !frames
    ; parse_errors = !parse_errors
    ; error_events = !error_events
    ; reconnects = List.sum (module Int) !opened ~f:Ws_client.reconnects
    }
  in
  let feed : Md.Feed.With_gaps.t =
    (module struct
      let trades = trades_r
      let bbo = bbo_r
      let l2 = l2_r
      let funding = funding_r
      let gaps = gaps_r
      let close () = Lazy_deferred.force_exn closed
    end)
  in
  return { feed; stats }
;;

let create_with_stats ?on_raw ?time_source config ~symbols ~streams =
  let%map t = connect ?on_raw ?time_source config ~symbols ~streams in
  feed t, t.stats
;;

let create ?on_raw ?time_source config ~symbols ~streams =
  connect ?on_raw ?time_source config ~symbols ~streams >>| feed
;;
