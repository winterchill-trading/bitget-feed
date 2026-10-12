(** Bitget public frames to {!Market_data} records. Pure apart from logging; the Async
    driver is {!Live_feed}.

    - [trade] pushes give one {!Market_data.Trade.t} per element ([exch_ts] = trade [ts],
      side = taker side), oldest first within a push. The snapshot of recent trades sent
      on subscribe is emitted too.
    - [books1] pushes give a {!Market_data.Bbo.t} ([exch_ts] = book [ts]).
    - [books] pushes go through a {!Local_book} per subscription and become
      {!Market_data.L2_update.t} snapshots and deltas. A [pseq] that does not continue the
      previous [seq], or a checksum mismatch, emits nothing and asks for a resubscribe;
      updates before the first snapshot are dropped. [books5]/[books15] pushes are full
      snapshots and pass through as such.
    - [ticker] pushes give a {!Market_data.Funding.t} when funding rate, next funding
      time, mark or index price changed since the last one emitted for that symbol. *)

open! Core

(** The channel a stream is read from: [trade], [books1], [books], [ticker]. Raises for
    [Private]. *)
val channel : Market_data.Stream.t -> string

val instrument : string -> Market_data.Instrument.t

module Output : sig
  type t =
    { events : Market_data.Event.t list
    ; resubscribe : Wire.Arg.t list (** subscriptions whose book lost sync *)
    }
  [@@deriving sexp_of]

  val empty : t
end

type t

val create : unit -> t

(** Acks and pongs give {!Output.empty}; [error] events give [Error]. *)
val message : t -> recv_ts:Time_ns.t -> Wire.Message.t -> Output.t Or_error.t

(** {!Wire.decode} then {!message}. *)
val frame : t -> recv_ts:Time_ns.t -> string -> Output.t Or_error.t
