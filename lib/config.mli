(** Where to connect and which market to read. *)

open! Core

type t =
  { url : Uri.t (** public websocket endpoint *)
  ; inst_type : string (** e.g. ["USDT-FUTURES"], ["COIN-FUTURES"], ["SPOT"] *)
  }
[@@deriving sexp_of]

(** [wss://ws.bitget.com/v2/ws/public] *)
val mainnet_url : Uri.t

(** USDT-margined perpetuals. *)
val default_inst_type : string

(** [create ()] is mainnet USDT futures; [url] overrides the endpoint (e.g. a local
    recorder or a proxy). *)
val create : ?url:Uri.t -> ?inst_type:string -> unit -> t
