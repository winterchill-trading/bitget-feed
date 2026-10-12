open! Core

let table =
  lazy
    (Array.init 256 ~f:(fun n ->
       let c = ref n in
       for _ = 1 to 8 do
         c := if !c land 1 = 1 then 0xEDB88320 lxor (!c lsr 1) else !c lsr 1
       done;
       !c))
;;

let crc32 s =
  let table = Lazy.force table in
  let crc =
    String.fold s ~init:0xFFFFFFFF ~f:(fun crc ch ->
      table.(crc lxor Char.to_int ch land 0xFF) lxor (crc lsr 8))
  in
  crc lxor 0xFFFFFFFF
;;

let crc32_signed s =
  let c = crc32 s in
  if c >= 0x80000000 then c - 0x100000000 else c
;;

let payload ?(depth = 25) ~bids ~asks () =
  let bids = List.take bids depth
  and asks = List.take asks depth in
  let level (px, sz) = [ px; sz ] in
  let rec interleave bids asks acc =
    match bids, asks with
    | [], [] -> List.rev acc
    | b :: bids, a :: asks ->
      interleave bids asks (List.rev_append (level b @ level a) acc)
    | b :: bids, [] -> interleave bids [] (List.rev_append (level b) acc)
    | [], a :: asks -> interleave [] asks (List.rev_append (level a) acc)
  in
  String.concat ~sep:":" (interleave bids asks [])
;;

let compute ?depth ~bids ~asks () = crc32_signed (payload ?depth ~bids ~asks ())
