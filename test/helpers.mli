(* Shared by the tests. *)

open! Core

(** [approx ~expected ~tolerance actual] prints as [expected+-tolerance] when [actual] is
    within [tolerance] of [expected], and as [actual] otherwise, so an expect test can pin
    an allocation count that differs by a few words between macOS and Linux. *)
val approx : expected:int -> tolerance:int -> int -> Sexp.t
