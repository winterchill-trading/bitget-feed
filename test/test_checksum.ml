open! Core
open Bitget_feed

let%expect_test "crc32 check value" =
  print_s
    [%sexp (Checksum.crc32 "123456789" : int), (Checksum.crc32_signed "123456789" : int)];
  [%expect {| (3421780262 -873187034) |}]
;;

let%expect_test "payload interleaves bids and asks, longer side continues" =
  print_endline
    (Checksum.payload
       ~bids:[ "100.5", "1"; "100.4", "2"; "100.3", "3" ]
       ~asks:[ "100.6", "4" ]
       ());
  [%expect {| 100.5:1:100.6:4:100.4:2:100.3:3 |}]
;;

let%expect_test "payload keeps 25 levels per side" =
  let side n = List.init 30 ~f:(fun i -> sprintf "%d" (n + i), "1") in
  let fields =
    String.split (Checksum.payload ~bids:(side 0) ~asks:(side 100) ()) ~on:':'
  in
  print_s [%sexp (List.length fields : int)];
  [%expect {| 100 |}]
;;

let%expect_test "compute" =
  print_s
    [%sexp
      (Checksum.compute ~bids:[ "82788.8", "0.4835" ] ~asks:[ "82789", "9.1278" ] ()
       : int)];
  [%expect {| 2094785069 |}]
;;
