(lang dune 3.17)

(name bitget-feed)

(generate_opam_files true)

(license MIT)

(maintainers "winterchill-trading")

(authors "winterchill-trading")

(source
 (github winterchill-trading/bitget-feed))

(package
 (name bitget-feed)
 (synopsis "Read-only public market data feed for Bitget USDT futures")
 (depends
  (ocaml
   (>= 5.2))
  dune
  core
  core_unix
  async
  async_ssl
  venue-net
  market-data
  ppx_jane
  ppx_yojson_conv
  yojson
  uri
  (async_websocket :with-test)
  (core_bench :with-test)))
