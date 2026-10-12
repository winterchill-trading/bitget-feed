open! Core

let approx ~expected ~tolerance actual =
  if abs (actual - expected) <= tolerance
  then Sexp.Atom (sprintf "%d+-%d" expected tolerance)
  else [%sexp (actual : int)]
;;

let%expect_test "approx" =
  List.iter [ 100; 105; 111 ] ~f:(fun actual ->
    print_s (approx ~expected:100 ~tolerance:10 actual));
  [%expect {|
    100+-10
    100+-10
    111
    |}]
;;
