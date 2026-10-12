(** The order book checksum older Bitget v2 docs describe for [books] pushes. *)

open! Core

(** CRC-32 (IEEE, as in zlib) of a string, as an unsigned value in [[0, 2^32)]. *)
val crc32 : string -> int

(** [crc32] read as a signed 32-bit integer, the form Bitget sends. *)
val crc32_signed : string -> int

(** The string the checksum covers: the first [depth] (default 25) bids and asks
    interleaved as [bid1px:bid1sz:ask1px:ask1sz:bid2px:...]. When one side runs out the
    other continues alone. Levels are the venue's original strings, best first. *)
val payload
  :  ?depth:int
  -> bids:(string * string) list
  -> asks:(string * string) list
  -> unit
  -> string

(** [crc32_signed (payload ...)] *)
val compute
  :  ?depth:int
  -> bids:(string * string) list
  -> asks:(string * string) list
  -> unit
  -> int
