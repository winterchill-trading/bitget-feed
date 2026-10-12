(** {!Normalizer} as a {!Market_data.Normalizer.S}, so [rebuild-norm] can turn
    market-recorder raw files of Bitget back into events:
    [Market_data.Rebuild_norm.command [ (module Bitget_feed.Raw_normalizer) ]].

    {!Normalizer} has no reset, so the state is a fresh normalizer behind a ref and a
    [disconnect] replaces it, dropping the local books as a reconnect does.
    Resubscriptions after a book loses sync are not sent (there is no connection); the
    book stays empty until the next snapshot in the recording. *)

include Market_data.Normalizer.S
