open! Core
module Md = Market_data

let channel : Md.Stream.t -> string = function
  | Trades -> "trade"
  | Bbo -> "books1"
  | L2 -> "books"
  | Funding -> "ticker"
  | Private -> raise_s [%message "Bitget feed: no public channel for the private stream"]
;;

let instrument inst_id = Md.Instrument.create Bitget inst_id
let time_of_ms ms = Time_ns.of_int_ns_since_epoch (Int.( * ) (Int.of_string ms) 1_000_000)

module Output = struct
  type t =
    { events : Md.Event.t list
    ; resubscribe : Wire.Arg.t list
    }
  [@@deriving sexp_of]

  let empty = { events = []; resubscribe = [] }
  let events events = { events; resubscribe = [] }
end

module Funding_key = struct
  type t =
    { rate : string
    ; next_funding_time : string
    ; mark : string
    ; index : string
    }
  [@@deriving equal]
end

type t =
  { books : Local_book.t Wire.Arg.Table.t
  ; funding : Funding_key.t String.Table.t (** last emitted, by instId *)
  }

let create () = { books = Wire.Arg.Table.create (); funding = String.Table.create () }

let side = function
  | "buy" -> Md.Side.Buy
  | "sell" -> Sell
  | other -> raise_s [%message "Bitget feed: unknown trade side" (other : string)]
;;

let trade ~recv_ts ~inst_id (trade : Wire.Trade.t) =
  Md.Event.Trade
    { instrument = instrument inst_id
    ; exch_ts = time_of_ms trade.ts
    ; recv_ts
    ; price = Md.Price.of_string trade.price
    ; size = Md.Size.of_string trade.size
    ; side = side trade.side
    ; trade_id = trade.trade_id
    }
;;

let levels levels =
  List.map levels ~f:(fun (px, sz) : Md.L2_update.Level.t ->
    { price = Md.Price.of_string px; size = Md.Size.of_string sz })
;;

let sorted_levels ~bids ~asks =
  ( List.sort (levels bids) ~compare:(fun (a : Md.L2_update.Level.t) b ->
      Md.Price.compare b.price a.price)
  , List.sort (levels asks) ~compare:(fun (a : Md.L2_update.Level.t) b ->
      Md.Price.compare a.price b.price) )
;;

let l2 ~recv_ts ~inst_id ~(kind : Md.L2_update.Kind.t) (book : Wire.Book.t) =
  let bids, asks =
    match kind with
    | Snapshot -> sorted_levels ~bids:book.bids ~asks:book.asks
    | Delta -> levels book.bids, levels book.asks
  in
  Md.Event.L2
    { instrument = instrument inst_id
    ; exch_ts = time_of_ms book.ts
    ; recv_ts
    ; kind
    ; bids
    ; asks
    }
;;

let bbo ~recv_ts ~inst_id (book : Wire.Book.t) =
  match sorted_levels ~bids:book.bids ~asks:book.asks with
  | bid :: _, ask :: _ ->
    [ Md.Event.Bbo
        { instrument = instrument inst_id
        ; exch_ts = time_of_ms book.ts
        ; recv_ts
        ; bid_price = bid.price
        ; bid_size = bid.size
        ; ask_price = ask.price
        ; ask_size = ask.size
        }
    ]
  | _ -> []
;;

let full_book t ~recv_ts (push : Wire.Push.t) (book : Wire.Book.t) : Output.t =
  let local = Hashtbl.find_or_add t.books push.arg ~default:Local_book.create in
  let inst_id = push.arg.inst_id in
  match Local_book.apply local push.action book with
  | Applied ->
    let kind : Md.L2_update.Kind.t =
      match push.action with
      | Snapshot -> Snapshot
      | Update -> Delta
    in
    Output.events [ l2 ~recv_ts ~inst_id ~kind book ]
  | Waiting_for_snapshot -> Output.empty
  | (Gap _ | Checksum_mismatch _) as result ->
    Async.Log.Global.info_s
      [%message
        "bitget feed: book out of sync, resubscribing"
          ~arg:(Wire.Arg.to_string push.arg)
          (result : Local_book.Result.t)];
    { events = []; resubscribe = [ push.arg ] }
;;

let books t ~recv_ts (push : Wire.Push.t) : Output.t Or_error.t =
  let%map.Or_error books = Wire.books push in
  let inst_id = push.arg.inst_id in
  match push.arg.channel with
  | "books" ->
    List.fold books ~init:Output.empty ~f:(fun (acc : Output.t) book ->
      let out = full_book t ~recv_ts push book in
      { events = acc.events @ out.events
      ; resubscribe = acc.resubscribe @ out.resubscribe
      })
  | "books1" -> Output.events (List.concat_map books ~f:(bbo ~recv_ts ~inst_id))
  | _ -> Output.events (List.map books ~f:(l2 ~recv_ts ~inst_id ~kind:Snapshot))
;;

let funding t ~recv_ts (ticker : Wire.Ticker.t) =
  match ticker with
  | { funding_rate = Some rate
    ; next_funding_time = Some next_funding_time
    ; mark_price = Some mark
    ; index_price = Some index
    ; _
    } ->
    let key = { Funding_key.rate; next_funding_time; mark; index } in
    (match Hashtbl.find t.funding ticker.inst_id with
     | Some last when Funding_key.equal last key -> []
     | Some _ | None ->
       let event =
         Md.Event.Funding
           { instrument = instrument ticker.inst_id
           ; exch_ts = time_of_ms ticker.ts
           ; recv_ts
           ; rate = Float.of_string rate
           ; next_funding_time = time_of_ms next_funding_time
           ; mark_price = Md.Price.of_string mark
           ; index_price = Md.Price.of_string index
           }
       in
       Hashtbl.set t.funding ~key:ticker.inst_id ~data:key;
       [ event ])
  | _ -> []
;;

let push t ~recv_ts (push : Wire.Push.t) : Output.t Or_error.t =
  match push.arg.channel with
  | "trade" ->
    let%map.Or_error trades = Wire.trades push in
    Output.events (List.map trades ~f:(trade ~recv_ts ~inst_id:push.arg.inst_id))
  | "ticker" ->
    let%map.Or_error tickers = Wire.tickers push in
    Output.events (List.concat_map tickers ~f:(funding t ~recv_ts))
  | channel when String.is_prefix channel ~prefix:"books" -> books t ~recv_ts push
  | _ -> Ok Output.empty
;;

let message t ~recv_ts (message : Wire.Message.t) =
  match message with
  | Pong -> Ok Output.empty
  | Event { event = "error"; arg; code; msg } ->
    Or_error.error_s
      [%message
        "bitget error event"
          ~arg:(Option.map arg ~f:Wire.Arg.to_string : string option)
          (code : string option)
          (msg : string option)]
  | Event _ -> Ok Output.empty
  | Push p ->
    Or_error.try_with_join (fun () -> push t ~recv_ts p)
    |> Or_error.tag ~tag:"Bitget feed: cannot normalize push"
;;

let frame t ~recv_ts frame =
  let%bind.Or_error decoded = Wire.decode frame in
  message t ~recv_ts decoded
;;
