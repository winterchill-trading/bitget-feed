open! Core
open Ppx_yojson_conv_lib.Yojson_conv.Primitives

module Arg = struct
  module T = struct
    type t =
      { inst_type : string [@key "instType"]
      ; channel : string
      ; inst_id : string [@key "instId"]
      }
    [@@deriving sexp, compare, equal, hash, yojson] [@@yojson.allow_extra_fields]
  end

  include T
  include Hashable.Make (T)

  let to_string { inst_type; channel; inst_id } =
    String.concat ~sep:"/" [ inst_type; channel; inst_id ]
  ;;
end

module Action = struct
  type t =
    | Snapshot
    | Update
  [@@deriving sexp, compare, equal]

  let of_string = function
    | "snapshot" -> Snapshot
    | "update" -> Update
    | other -> raise_s [%message "Wire: unknown action" (other : string)]
  ;;
end

module Trade = struct
  type t =
    { ts : string
    ; price : string
    ; size : string
    ; side : string
    ; trade_id : string [@key "tradeId"]
    }
  [@@deriving sexp, yojson] [@@yojson.allow_extra_fields]
end

module Ticker = struct
  type t =
    { inst_id : string [@key "instId"]
    ; bid_pr : string option
         [@key "bidPr"] [@default None] [@yojson_drop_if Option.is_none]
    ; ask_pr : string option
         [@key "askPr"] [@default None] [@yojson_drop_if Option.is_none]
    ; bid_sz : string option
         [@key "bidSz"] [@default None] [@yojson_drop_if Option.is_none]
    ; ask_sz : string option
         [@key "askSz"] [@default None] [@yojson_drop_if Option.is_none]
    ; funding_rate : string option
         [@key "fundingRate"] [@default None] [@yojson_drop_if Option.is_none]
    ; next_funding_time : string option
         [@key "nextFundingTime"] [@default None] [@yojson_drop_if Option.is_none]
    ; mark_price : string option
         [@key "markPrice"] [@default None] [@yojson_drop_if Option.is_none]
    ; index_price : string option
         [@key "indexPrice"] [@default None] [@yojson_drop_if Option.is_none]
    ; ts : string
    }
  [@@deriving sexp, yojson] [@@yojson.allow_extra_fields]
end

module Book = struct
  type t =
    { asks : (string * string) list
    ; bids : (string * string) list
    ; ts : string
    ; seq : int option [@default None] [@yojson_drop_if Option.is_none]
    ; pseq : int option [@default None] [@yojson_drop_if Option.is_none]
    ; checksum : int option [@default None] [@yojson_drop_if Option.is_none]
    }
  [@@deriving sexp, yojson] [@@yojson.allow_extra_fields]
end

module Push = struct
  type t =
    { action : Action.t
    ; arg : Arg.t
    ; data : Yojson.Safe.t list
    ; ts : int option
    }

  let sexp_of_t { action; arg; data; ts } =
    [%sexp
      { action : Action.t
      ; arg : Arg.t
      ; data = (List.map data ~f:Yojson.Safe.to_string : string list)
      ; ts : int option
      }]
  ;;
end

module Event = struct
  type t =
    { event : string
    ; arg : Arg.t option
    ; code : string option
    ; msg : string option
    }
  [@@deriving sexp_of]
end

module Message = struct
  type t =
    | Pong
    | Event of Event.t
    | Push of Push.t
  [@@deriving sexp_of]
end

let member key = function
  | `Assoc fields -> List.Assoc.find fields key ~equal:String.equal
  | _ -> None
;;

let string_member key json =
  match member key json with
  | Some (`String s) -> Some s
  | Some (`Int i) -> Some (Int.to_string i)
  | Some (`Intlit s) -> Some s
  | Some `Null | None -> None
  | Some other ->
    raise_s [%message "Wire: expected a string" key (Yojson.Safe.to_string other)]
;;

let int_member key json =
  match member key json with
  | Some (`Int i) -> Some i
  | Some (`String s) -> Some (Int.of_string s)
  | Some `Null | None -> None
  | Some other ->
    raise_s [%message "Wire: expected an int" key (Yojson.Safe.to_string other)]
;;

let of_json json : Message.t =
  match member "event" json, member "action" json with
  | Some (`String event), _ ->
    Event
      { event
      ; arg = Option.map (member "arg" json) ~f:Arg.t_of_yojson
      ; code = string_member "code" json
      ; msg = string_member "msg" json
      }
  | None, Some (`String action) ->
    let arg =
      match member "arg" json with
      | Some arg -> Arg.t_of_yojson arg
      | None -> raise_s [%message "Wire: push without arg"]
    in
    let data =
      match member "data" json with
      | Some (`List data) -> data
      | Some _ | None -> raise_s [%message "Wire: push without a data list"]
    in
    Push { action = Action.of_string action; arg; data; ts = int_member "ts" json }
  | _ -> raise_s [%message "Wire: neither an event nor a push"]
;;

let decode frame =
  match String.strip frame with
  | "pong" -> Ok Message.Pong
  | stripped ->
    Or_error.try_with (fun () -> of_json (Yojson.Safe.from_string stripped))
    |> Or_error.tag ~tag:"Wire.decode"
;;

let data (push : Push.t) ~f =
  Or_error.try_with (fun () -> List.map push.data ~f)
  |> Or_error.tag_s ~tag:[%message "Wire: bad data" ~arg:(Arg.to_string push.arg)]
;;

let trades push = data push ~f:Trade.t_of_yojson
let tickers push = data push ~f:Ticker.t_of_yojson
let books push = data push ~f:Book.t_of_yojson

let request op args =
  Yojson.Safe.to_string
    (`Assoc [ "op", `String op; "args", `List (List.map args ~f:Arg.yojson_of_t) ])
;;

let subscribe args = request "subscribe" args
let unsubscribe args = request "unsubscribe" args
let ping = "ping"
