(* Minor words allocated per Live_feed message: what [Normalizer.frame] (decode plus
   normalization, the work Live_feed does per websocket frame) allocates on the recorded
   minute. The timing benchmark is in bench/. Counts differ by a few words between macOS
   and Linux, hence [Helpers.approx], with a tolerance of 10 words or 0.2%. *)

open! Core
open Bitget_feed
module Md = Market_data

let dir = "fixtures/bitget-BTCUSDT-2026-10-12T16-54"
let streams : Md.Stream.t list = [ Trades; Bbo; L2; Funding ]

let frames stream =
  In_channel.read_lines (dir ^/ Md.Stream.to_string stream ^ ".ndjson")
  |> List.map ~f:(fun line ->
    let recv_ts, frame = String.lsplit2_exn line ~on:' ' in
    Time_ns.of_string_with_utc_offset recv_ts, frame)
;;

let words f =
  let before = Gc.minor_words () in
  f ();
  Gc.minor_words () - before
;;

(* Pinned counts. macOS and Linux differ by a few words; [Helpers.approx] allows 10 words
   or 0.2%, whichever is larger. *)
let expected : Md.Stream.t -> int = function
  | Trades -> 751
  | Bbo -> 565
  | L2 -> 15447
  | Funding -> 776
  | Private -> 0
;;

let%expect_test "minor words per Live_feed message" =
  List.iter streams ~f:(fun stream ->
    let t = Normalizer.create () in
    let frames = frames stream in
    let total =
      List.sum (module Int) frames ~f:(fun (recv_ts, frame) ->
        words (fun () ->
          ignore
            (Sys.opaque_identity (Normalizer.frame t ~recv_ts frame)
             : Normalizer.Output.t Or_error.t)))
    in
    let n = List.length frames in
    let bytes = List.sum (module Int) frames ~f:(fun (_, frame) -> String.length frame) in
    print_s
      [%message
        ""
          (stream : Md.Stream.t)
          ~frames:(n : int)
          ~words_per_frame:
            (let expected = expected stream in
             Helpers.approx ~expected ~tolerance:(Int.max 10 (expected / 500)) (total / n)
             : Sexp.t)
          ~bytes_per_frame:(bytes / n : int)]);
  [%expect
    {|
    ((stream Trades) (frames 150) (words_per_frame 751+-10)
     (bytes_per_frame 383))
    ((stream Bbo) (frames 200) (words_per_frame 565+-10) (bytes_per_frame 230))
    ((stream L2) (frames 40) (words_per_frame 15447+-30) (bytes_per_frame 2022))
    ((stream Funding) (frames 60) (words_per_frame 776+-10)
     (bytes_per_frame 581))
    |}]
;;
