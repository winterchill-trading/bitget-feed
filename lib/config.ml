open! Core

type t =
  { url : Uri.t
  ; inst_type : string
  }

let sexp_of_t { url; inst_type } =
  [%sexp { url = (Uri.to_string url : string); inst_type : string }]
;;

let mainnet_url = Uri.of_string "wss://ws.bitget.com/v2/ws/public"
let default_inst_type = "USDT-FUTURES"
let create ?(url = mainnet_url) ?(inst_type = default_inst_type) () = { url; inst_type }
