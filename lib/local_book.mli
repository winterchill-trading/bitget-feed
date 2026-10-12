(** A local copy of one [books] subscription, used to check [seq]/[pseq] continuity and,
    when present, the checksum. *)

open! Core

type t

val create : unit -> t

module Result : sig
  type t =
    | Applied
    | Waiting_for_snapshot (** an update before any snapshot (or after a gap); dropped *)
    | Gap of
        { expected : int (** the [seq] of the previous push *)
        ; received : int (** the [pseq] of this one *)
        }
    | Checksum_mismatch of
        { expected : int
        ; computed : int
        }
  [@@deriving sexp_of, equal]
end

(** A [Snapshot] replaces the book. An [Update] must carry [pseq] equal to the [seq] of
    the previous push; then its levels are applied (size zero deletes). Pushes without
    [seq]/[pseq] are not checked. After a [Gap] or [Checksum_mismatch] the book is cleared
    and waits for the next snapshot. Raises on unparsable prices or sizes. *)
val apply : t -> Wire.Action.t -> Wire.Book.t -> Result.t

val is_synced : t -> bool

(** Levels as received (original strings), best first. *)
val bids : ?depth:int -> t -> (string * string) list

val asks : ?depth:int -> t -> (string * string) list
