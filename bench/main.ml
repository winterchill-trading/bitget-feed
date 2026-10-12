(* Normalizer.frame (decode plus normalization, the work Live_feed does per websocket
   frame) on the recorded mainnet minute in test/fixtures.

   Each benchmark cycles through the frames of one stream in recording order, one frame
   per run, with one normalizer. The L2 cycle starts with the subscribe ack and the
   snapshot, so every pass resets the book and the deltas keep matching [pseq]. *)

open! Core
open Core_bench
open Bitget_feed

let frames text =
  String.split_lines text
  |> List.filter_map ~f:(fun line ->
    Option.map (String.lsplit2 line ~on:' ') ~f:(fun (_recv_ts, frame) -> frame))
  |> Array.of_list
;;

let per_frame name text =
  let frames = frames text in
  let t = Normalizer.create () in
  let i = ref 0 in
  Bench.Test.create ~name (fun () ->
    let frame = frames.(!i) in
    i := (!i + 1) % Array.length frames;
    ignore
      (Normalizer.frame t ~recv_ts:Time_ns.epoch frame : Normalizer.Output.t Or_error.t))
;;

let () =
  Command_unix.run
    (Bench.make_command
       [ per_frame "trades" Frames.trades
       ; per_frame "bbo" Frames.bbo
       ; per_frame "l2" Frames.l2
       ; per_frame "funding" Frames.funding
       ])
;;
