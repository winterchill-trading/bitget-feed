open! Core
open Bitget_feed

let decode frame =
  match Wire.decode frame with
  | Ok message -> print_s [%sexp (message : Wire.Message.t)]
  | Error _ -> print_endline "error"
;;

let%expect_test "pong, acks and errors" =
  decode "pong";
  decode
    {|{"event":"subscribe","arg":{"instType":"USDT-FUTURES","channel":"trade","instId":"BTCUSDT"}}|};
  decode
    {|{"event":"error","arg":{"instType":"USDT-FUTURES","channel":"bogus","instId":"BTCUSDT"},"code":30016,"msg":"Param error","op":"subscribe"}|};
  decode {|{"event":"error","code":"30002","msg":"Unrecognized request:{bad"}|};
  [%expect
    {|
    Pong
    (Event
     ((event subscribe)
      (arg (((inst_type USDT-FUTURES) (channel trade) (inst_id BTCUSDT))))
      (code ()) (msg ())))
    (Event
     ((event error)
      (arg (((inst_type USDT-FUTURES) (channel bogus) (inst_id BTCUSDT))))
      (code (30016)) (msg ("Param error"))))
    (Event
     ((event error) (arg ()) (code (30002)) (msg ("Unrecognized request:{bad"))))
    |}]
;;

let%expect_test "push envelope and book data" =
  let frame =
    {|{"action":"update","arg":{"instType":"USDT-FUTURES","channel":"books","instId":"BTCUSDT"},"data":[{"asks":[["82789","9.1278"],["82792.4","0"]],"bids":[["82785.7","0"]],"ts":"1791808998701","seq":1091176380793,"pseq":1091176375385}],"ts":1791808998703}|}
  in
  let push =
    match Wire.decode frame with
    | Ok (Push push) -> push
    | _ -> assert false
  in
  print_s [%sexp (push.action : Wire.Action.t), (push.ts : int option)];
  print_s [%sexp (Wire.books push : Wire.Book.t list Or_error.t)];
  [%expect
    {|
    (Update (1791808998703))
    (Ok
     (((asks ((82789 9.1278) (82792.4 0))) (bids ((82785.7 0)))
       (ts 1791808998701) (seq (1091176380793)) (pseq (1091176375385))
       (checksum ()))))
    |}]
;;

let%expect_test "bad frames" =
  decode "{not json";
  decode {|{"foo":1}|};
  decode {|{"action":"snapshot","arg":{"instType":"X","channel":"trade","instId":"Y"}}|};
  decode
    {|{"action":"merge","arg":{"instType":"X","channel":"trade","instId":"Y"},"data":[]}|};
  [%expect {|
    error
    error
    error
    error
    |}]
;;

let%expect_test "requests" =
  let arg : Wire.Arg.t =
    { inst_type = "USDT-FUTURES"; channel = "books"; inst_id = "BTCUSDT" }
  in
  print_endline (Wire.subscribe [ arg ]);
  print_endline (Wire.unsubscribe [ arg ]);
  [%expect
    {|
    {"op":"subscribe","args":[{"instType":"USDT-FUTURES","channel":"books","instId":"BTCUSDT"}]}
    {"op":"unsubscribe","args":[{"instType":"USDT-FUTURES","channel":"books","instId":"BTCUSDT"}]}
    |}]
;;
