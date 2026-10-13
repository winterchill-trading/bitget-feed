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
  ; writers : Writer.t Queue.t (** each connection's socket writer *)
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

(** [payload] as one websocket text frame from the server, header included. *)
val encode_text_frame : string -> string

(** Writes already encoded frames (see {!encode_text_frame}) straight to the newest
    connection's socket, so a burst costs the server almost nothing per frame. *)
val write_raw : t -> string -> unit

(** Close the [n]th (0-based) server-side socket, as a server restart would. *)
val drop : t -> int -> unit Deferred.t

val close : t -> unit Deferred.t
