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

    [recv_ts] is the time of [time_source] (default the wall clock) when the frame is
    read. [time_source] also drives the keepalive, the silence watchdog and the
    reconnection delay of every connection (see {!Venue_net.Ws_client.connect}), so tests
    can step them with a synthetic clock. [on_raw] gets that frame unparsed, first,
    including acks and pongs. Undecodable frames and error events are logged and skipped.
    Pipes of streams that were not requested stay empty until [close]. Writes do not wait
    for readers, so consumers should keep up. *)

open! Core
open Async

module Stats : sig
  type t =
    { frames : int (** text frames received, acks and pongs included *)
    ; parse_errors : int
    (** frames that did not decode or normalize (bad JSON, unknown shape, bad numbers) and
        were dropped *)
    ; error_events : int (** [{"event": "error"}] responses from the server *)
    ; reconnects : int (** successful reconnections, summed over the connections *)
    }
  [@@deriving sexp_of]
end

type t

(** Raises if a first connection fails, or if [streams] contains [Private]. *)
val connect
  :  ?on_raw:(stream:Market_data.Stream.t -> recv_ts:Time_ns.t -> string -> unit)
  -> ?time_source:Time_source.t
  -> Config.t
  -> symbols:string list
  -> streams:Market_data.Stream.t list
  -> t Deferred.t

module For_testing : sig
  (** {!connect} with the delivery used before [on_message]: frames are read from
      {!Venue_net.Ws_client.messages} one at a time. The reference for tests and the
      bench. *)
  val connect_via_messages
    :  ?on_raw:(stream:Market_data.Stream.t -> recv_ts:Time_ns.t -> string -> unit)
    -> ?time_source:Time_source.t
    -> Config.t
    -> symbols:string list
    -> streams:Market_data.Stream.t list
    -> t Deferred.t
end

val feed : t -> Market_data.Feed.t

(** The same feed with its [gaps] pipe (see above). *)
val feed_with_gaps : t -> Market_data.Feed.With_gaps.t

val stats : t -> Stats.t

(** [connect] then [feed]. *)
val create
  :  ?on_raw:(stream:Market_data.Stream.t -> recv_ts:Time_ns.t -> string -> unit)
  -> ?time_source:Time_source.t
  -> Config.t
  -> symbols:string list
  -> streams:Market_data.Stream.t list
  -> Market_data.Feed.t Deferred.t

(** [connect], returning [feed] and a function that reads the current counters. *)
val create_with_stats
  :  ?on_raw:(stream:Market_data.Stream.t -> recv_ts:Time_ns.t -> string -> unit)
  -> ?time_source:Time_source.t
  -> Config.t
  -> symbols:string list
  -> streams:Market_data.Stream.t list
  -> (Market_data.Feed.t * (unit -> Stats.t)) Deferred.t

(** The subscription for a stream and symbol. *)
val arg : Config.t -> Market_data.Stream.t -> string -> Wire.Arg.t
