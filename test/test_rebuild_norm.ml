(* [rebuild-norm] over the recorded fixture minute, laid out as market-recorder raw files,
   with [Raw_normalizer]; the event logs are read back. *)

open! Core
open! Async
open Bitget_feed
module Md = Market_data

let fixture_dir = "fixtures/bitget-BTCUSDT-2026-10-12T16-54"
let date = Date.of_string "2026-10-12"
let streams : Md.Stream.t list = [ Trades; Bbo; L2; Funding ]

let with_temp_dir f =
  let%bind dir = Unix.mkdtemp (Filename.temp_dir_name ^/ "bitget-feed-test") in
  Monitor.protect
    (fun () -> f dir)
    ~finally:(fun () ->
      Process.run_expect_no_stdout_exn ~prog:"rm" ~args:[ "-rf"; dir ] ())
;;

let write_raw ~data_dir =
  Deferred.List.iter streams ~how:`Sequential ~f:(fun stream ->
    let stream = Md.Stream.to_string stream in
    let day = data_dir ^/ "raw/bitget" ^/ stream ^/ "BTCUSDT/2026/10/12" in
    let%bind () = Unix.mkdir ~p:() day in
    let%bind contents = Reader.file_contents (fixture_dir ^/ stream ^ ".ndjson") in
    Writer.save (day ^/ "16-54.ndjson") ~contents)
;;

let%expect_test "rebuild the fixture minute and read the event logs back" =
  with_temp_dir (fun data_dir ->
    let%bind () = write_raw ~data_dir in
    let out_dir = data_dir ^/ "rebuilt" in
    let%bind stats =
      Md.Rebuild_norm.run ~normalizers:[ (module Raw_normalizer) ] ~data_dir ~out_dir date
    in
    print_s [%sexp (stats : Md.Rebuild_norm.Stats.t Or_error.t)];
    let instrument = Normalizer.instrument "BTCUSDT" in
    let%map () =
      Deferred.List.iter streams ~how:`Sequential ~f:(fun stream ->
        let%map events, tail =
          Md.Event_log.load_file (Md.Event_log.path ~dir:out_dir instrument stream date)
        in
        let recv_ts =
          List.map events ~f:(fun (event : Md.Event.t) ->
            match event with
            | Trade x -> x.recv_ts
            | Bbo x -> x.recv_ts
            | L2 x -> x.recv_ts
            | Funding x -> x.recv_ts)
        in
        print_s
          [%message
            ""
              (stream : Md.Stream.t)
              ~events:(List.length events : int)
              ~recv_ts_sorted:(List.is_sorted recv_ts ~compare:Time_ns.compare : bool)
              (tail : Md.Framed.Tail.t)])
    in
    [%expect
      {|
      (Ok
       ((files 4) (frames 450) (disconnects 0) (events 649) (frame_errors 0)
        (first_errors ()) (skipped_files 0) (skipped_venues ())))
      ((stream Trades) (events 392) (recv_ts_sorted true) (tail Clean))
      ((stream Bbo) (events 199) (recv_ts_sorted true) (tail Clean))
      ((stream L2) (events 39) (recv_ts_sorted true) (tail Clean))
      ((stream Funding) (events 19) (recv_ts_sorted true) (tail Clean))
      |}])
;;
