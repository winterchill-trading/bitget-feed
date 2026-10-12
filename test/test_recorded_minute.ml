(* A trimmed minute of mainnet frames in the market-recorder raw format
   ([<recv_ts> <frame>] per line, one file per stream), decoded and normalized. *)

open! Core
open Bitget_feed
module Md = Market_data

let dir = "fixtures/bitget-BTCUSDT-2026-10-12T16-54"
let streams : Md.Stream.t list = [ Trades; Bbo; L2; Funding ]

let lines stream =
  In_channel.read_lines (dir ^/ Md.Stream.to_string stream ^ ".ndjson")
  |> List.map ~f:(fun line ->
    let recv_ts, frame = String.lsplit2_exn line ~on:' ' in
    Time_ns.of_string_with_utc_offset recv_ts, frame)
;;

let stream_of_event : Md.Event.t -> Md.Stream.t = function
  | Trade _ -> Trades
  | Bbo _ -> Bbo
  | L2 _ -> L2
  | Funding _ -> Funding
;;

let%expect_test "every recorded frame decodes and normalizes" =
  List.iter streams ~f:(fun file_stream ->
    let frames = lines file_stream in
    let decode_errors =
      List.count frames ~f:(fun (_, frame) -> Or_error.is_error (Wire.decode frame))
    in
    let normalizer = Normalizer.create () in
    let normalize_errors = ref 0 in
    let resubscribes = ref 0 in
    let events = Hashtbl.create (module Md.Stream) in
    List.iter frames ~f:(fun (recv_ts, frame) ->
      match Normalizer.frame normalizer ~recv_ts frame with
      | Error _ -> incr normalize_errors
      | Ok { events = normalized; resubscribe } ->
        resubscribes := !resubscribes + List.length resubscribe;
        List.iter normalized ~f:(fun event -> Hashtbl.incr events (stream_of_event event)));
    print_s
      [%message
        ""
          ~file:(file_stream : Md.Stream.t)
          ~frames:(List.length frames : int)
          (decode_errors : int)
          ~normalize_errors:(!normalize_errors : int)
          ~resubscribes:(!resubscribes : int)
          ~events:
            (Hashtbl.to_alist events |> List.sort ~compare:[%compare: Md.Stream.t * int]
             : (Md.Stream.t * int) list)]);
  [%expect
    {|
    ((file Trades) (frames 150) (decode_errors 0) (normalize_errors 0)
     (resubscribes 0) (events ((Trades 392))))
    ((file Bbo) (frames 200) (decode_errors 0) (normalize_errors 0)
     (resubscribes 0) (events ((Bbo 199))))
    ((file L2) (frames 40) (decode_errors 0) (normalize_errors 0)
     (resubscribes 0) (events ((L2 39))))
    ((file Funding) (frames 60) (decode_errors 0) (normalize_errors 0)
     (resubscribes 0) (events ((Funding 19))))
    |}]
;;
