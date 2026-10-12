open! Core
module Price = Market_data.Price
module Size = Market_data.Size

module Result = struct
  type t =
    | Applied
    | Waiting_for_snapshot
    | Gap of
        { expected : int
        ; received : int
        }
    | Checksum_mismatch of
        { expected : int
        ; computed : int
        }
  [@@deriving sexp_of, equal]
end

type side = (string * string) Map.M(Price).t

type t =
  { mutable bids : side
  ; mutable asks : side
  ; mutable synced : bool
  ; mutable last_seq : int option
  }

let empty : side = Map.empty (module Price)
let create () = { bids = empty; asks = empty; synced = false; last_seq = None }

let reset t =
  t.bids <- empty;
  t.asks <- empty;
  t.synced <- false;
  t.last_seq <- None
;;

let apply_levels side levels =
  List.fold levels ~init:side ~f:(fun side ((px, sz) as level) ->
    let price = Price.of_string px in
    if Size.is_zero (Size.of_string sz)
    then Map.remove side price
    else Map.set side ~key:price ~data:level)
;;

let take side ~depth ~descending =
  let order = if descending then `Decreasing_key else `Increasing_key in
  Map.to_sequence side ~order
  |> Fn.flip Sequence.take depth
  |> Sequence.map ~f:snd
  |> Sequence.to_list
;;

let bids ?(depth = Int.max_value) t = take t.bids ~depth ~descending:true
let asks ?(depth = Int.max_value) t = take t.asks ~depth ~descending:false

let check_checksum t (book : Wire.Book.t) : Result.t =
  match book.checksum with
  | None | Some 0 -> Applied
  | Some expected ->
    let computed =
      Checksum.compute ~bids:(bids ~depth:25 t) ~asks:(asks ~depth:25 t) ()
    in
    if expected = computed
    then Applied
    else (
      reset t;
      Checksum_mismatch { expected; computed })
;;

let apply t (action : Wire.Action.t) (book : Wire.Book.t) : Result.t =
  match action with
  | Snapshot ->
    t.bids <- apply_levels empty book.bids;
    t.asks <- apply_levels empty book.asks;
    t.synced <- true;
    t.last_seq <- book.seq;
    check_checksum t book
  | Update when not t.synced -> Waiting_for_snapshot
  | Update ->
    (match t.last_seq, book.pseq with
     | Some expected, Some received when expected <> received ->
       reset t;
       Gap { expected; received }
     | _ ->
       t.bids <- apply_levels t.bids book.bids;
       t.asks <- apply_levels t.asks book.asks;
       t.last_seq <- book.seq;
       check_checksum t book)
;;

let is_synced t = t.synced
