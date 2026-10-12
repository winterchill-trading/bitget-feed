(* A Bitget-like websocket server on 127.0.0.1 for tests, built from async_websocket with
   [~role:Server]. *)

open! Core
open Async
module Wire = Bitget_feed.Wire

type t =
  { tcp : (Socket.Address.Inet.t, int) Tcp.Server.t
  ; received : (int * string) Queue.t
  ; sockets : string Websocket.t Queue.t
  }

let rec read_headers reader acc =
  match%bind Reader.read_line reader with
  | `Eof | `Ok "" -> return acc
  | `Ok line ->
    read_headers
      reader
      (match String.lsplit2 line ~on:':' with
       | Some (k, v) -> (String.lowercase (String.strip k), String.strip v) :: acc
       | None -> acc)
;;

let args_of_request frame =
  match Yojson.Safe.from_string frame with
  | `Assoc fields ->
    (match
       ( List.Assoc.find fields ~equal:String.equal "op"
       , List.Assoc.find fields ~equal:String.equal "args" )
     with
     | Some (`String op), Some (`List args) ->
       Some (op, List.map args ~f:Wire.Arg.t_of_yojson)
     | _ -> None)
  | _ -> None
  | exception _ -> None
;;

let reply ~on_subscribe to_client n frame =
  if String.equal frame Wire.ping
  then Pipe.write_without_pushback to_client "pong"
  else (
    match args_of_request frame with
    | Some ("subscribe", args) ->
      List.iter args ~f:(fun arg ->
        Pipe.write_without_pushback
          to_client
          (Yojson.Safe.to_string
             (`Assoc [ "event", `String "subscribe"; "arg", Wire.Arg.yojson_of_t arg ]));
        List.iter
          (on_subscribe ~connection:n arg)
          ~f:(Pipe.write_without_pushback to_client))
    | _ -> ())
;;

let handle ~greeting ~on_subscribe ~received ~sockets reader writer =
  let%bind headers = read_headers reader [] in
  let key = List.Assoc.find_exn headers ~equal:String.equal "sec-websocket-key" in
  Writer.write
    writer
    (sprintf
       "HTTP/1.1 101 Switching Protocols\r\n\
        Upgrade: websocket\r\n\
        Connection: Upgrade\r\n\
        Sec-WebSocket-Accept: %s\r\n\
        \r\n"
       (Websocket.sec_websocket_accept_header_value ~sec_websocket_key:key));
  let ws = Websocket.create ~opcode:`Text ~role:Server reader writer in
  Queue.enqueue sockets ws;
  let n = Queue.length sockets in
  let from_client, to_client = Websocket.pipes ws in
  if n = 1 then List.iter greeting ~f:(Pipe.write_without_pushback to_client);
  Pipe.iter_without_pushback from_client ~f:(fun frame ->
    Queue.enqueue received (n, frame);
    reply ~on_subscribe to_client n frame)
;;

let start ?(greeting = []) ?(on_subscribe = fun ~connection:_ _ -> []) () =
  let received = Queue.create () in
  let sockets = Queue.create () in
  let%map tcp =
    Tcp.Server.create
      ~on_handler_error:`Ignore
      Tcp.Where_to_listen.of_port_chosen_by_os
      (fun _ reader writer ->
         handle ~greeting ~on_subscribe ~received ~sockets reader writer)
  in
  { tcp; received; sockets }
;;

let url t =
  Uri.of_string (sprintf "ws://127.0.0.1:%d/v2/ws/public" (Tcp.Server.listening_on t.tcp))
;;

let drop t n =
  Websocket.close (Queue.get t.sockets n) ~code:Endpoint_going_away ~reason:"restart"
;;

let close t = Tcp.Server.close ~close_existing_connections:true t.tcp
