(** Bitget v2 public websocket messages, as sent on the wire. Prices, sizes and timestamps
    inside [data] stay strings here; {!Normalizer} parses them. *)

open! Core

(** A subscription: [{"instType", "channel", "instId"}]. *)
module Arg : sig
  type t =
    { inst_type : string
    ; channel : string
    ; inst_id : string
    }
  [@@deriving sexp, compare, equal, hash, yojson]

  include Hashable.S with type t := t

  (** ["USDT-FUTURES/books/BTCUSDT"] *)
  val to_string : t -> string
end

module Action : sig
  type t =
    | Snapshot
    | Update
  [@@deriving sexp, compare, equal]
end

(** One element of a [trade] push. *)
module Trade : sig
  type t =
    { ts : string
    ; price : string
    ; size : string
    ; side : string (** taker side, ["buy"] or ["sell"] *)
    ; trade_id : string
    }
  [@@deriving sexp, yojson]
end

(** One element of a [ticker] push; only the fields this feed uses. Funding fields are
    absent on spot. *)
module Ticker : sig
  type t =
    { inst_id : string
    ; bid_pr : string option
    ; ask_pr : string option
    ; bid_sz : string option
    ; ask_sz : string option
    ; funding_rate : string option
    ; next_funding_time : string option
    ; mark_price : string option
    ; index_price : string option
    ; ts : string
    }
  [@@deriving sexp, yojson]
end

(** One element of a [books*] push. Levels are [[price; size]] string pairs. *)
module Book : sig
  type t =
    { asks : (string * string) list
    ; bids : (string * string) list
    ; ts : string
    ; seq : int option
    ; pseq : int option
    ; checksum : int option
    }
  [@@deriving sexp, yojson]
end

module Push : sig
  type t =
    { action : Action.t
    ; arg : Arg.t
    ; data : Yojson.Safe.t list
    ; ts : int option (** outer send time, ms *)
    }
  [@@deriving sexp_of]
end

(** [{"event": ...}] responses: subscription acks and errors. *)
module Event : sig
  type t =
    { event : string (** ["subscribe"], ["unsubscribe"], ["error"], ... *)
    ; arg : Arg.t option
    ; code : string option (** a JSON number or string on the wire *)
    ; msg : string option
    }
  [@@deriving sexp_of]
end

module Message : sig
  type t =
    | Pong (** the text frame ["pong"] *)
    | Event of Event.t
    | Push of Push.t
  [@@deriving sexp_of]
end

(** Decodes one text frame. [Error] for invalid JSON or an unrecognised object. *)
val decode : string -> Message.t Or_error.t

(** The data elements of a push, decoded. *)
val trades : Push.t -> Trade.t list Or_error.t

val tickers : Push.t -> Ticker.t list Or_error.t
val books : Push.t -> Book.t list Or_error.t

(** Client requests. *)

val subscribe : Arg.t list -> string
val unsubscribe : Arg.t list -> string

(** The keepalive text frame, ["ping"]. *)
val ping : string
