(** A live {!Market_data.Feed.t} over Bitget's v2 public websocket. Read-only, no
    credentials.

    Each requested stream gets its own {!Venue_net.Ws_client} connection, so every frame
    is known to belong to one stream (see {!Normalizer.channel} for the channels). The
    client sends the text frame ["ping"] every 30 seconds; a connection that stays silent
    for two intervals is replaced.

    On every (re)connection all symbols are subscribed again; Bitget answers each
    subscription to [books] with a fresh snapshot, so the L2 stream restarts with a
    [Snapshot] after a reconnect. A book that loses sync is resubscribed (unsubscribe then
    subscribe).

    [recv_ts] is [Time_ns.now ()] when the frame is read. [on_raw] gets that frame
    unparsed, first, including acks and pongs. Undecodable frames and error events are
    logged and skipped. Pipes of streams that were not requested stay empty until [close].
    Writes do not wait for readers, so consumers should keep up. *)

open! Core
open Async

(** Raises if a first connection fails, or if [streams] contains [Private]. *)
val create
  :  ?on_raw:(stream:Market_data.Stream.t -> recv_ts:Time_ns.t -> string -> unit)
  -> Config.t
  -> symbols:string list
  -> streams:Market_data.Stream.t list
  -> Market_data.Feed.t Deferred.t

(** The subscription for a stream and symbol. *)
val arg : Config.t -> Market_data.Stream.t -> string -> Wire.Arg.t
