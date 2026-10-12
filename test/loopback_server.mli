(** A Bitget-like websocket server on 127.0.0.1 for tests.

    It answers the upgrade handshake on any path, acknowledges every subscription of a
    [{"op":"subscribe"}] request with a [{"event":"subscribe"}] frame followed by the
    frames of [on_subscribe], and answers the text frame ["ping"] with ["pong"].
    Connections are numbered from 1. *)

open! Core
open Async

type t =
  { tcp : (Socket.Address.Inet.t, int) Tcp.Server.t
  ; received : (int * string) Queue.t (** (connection number, frame) *)
  ; sockets : string Websocket.t Queue.t
  }

(** [greeting] (default none) is sent once, on the first connection. [on_subscribe]
    defaults to no frames. *)
val start
  :  ?greeting:string list
  -> ?on_subscribe:(connection:int -> Bitget_feed.Wire.Arg.t -> string list)
  -> unit
  -> t Deferred.t

(** [ws://127.0.0.1:<port>/v2/ws/public] *)
val url : t -> Uri.t

(** Close the [n]th (0-based) server-side socket, as a server restart would. *)
val drop : t -> int -> unit Deferred.t

val close : t -> unit Deferred.t
