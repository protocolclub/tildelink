type t = Uri.t

let of_uri uri =
  match Uri.scheme uri with
  | Some "tilde" ->
    begin match Uri.userinfo uri, Uri.port uri, Uri.fragment uri with
    | None, None, None ->
      let path = Uri.path uri in
      if String.length path > 0 && String.get path 0 = '/' then
        (* hack; see https://github.com/mirage/ocaml-uri/issues/57 *)
        begin match Uri.query uri with
        | [key, []] when String.length key = 43 -> `Ok uri
        | _ -> `Error "query must be a base64-encoded Curve25519 public key"
        end
      else `Error "path must be absolute"
    | _ -> `Error "userinfo, port and fragment must be empty"
    end
  | _ -> `Error "scheme must be tilde://"

let to_uri uri = uri

let make ~domain ~path ~public_key =
  let public_key = Base64.encode ~alphabet:Base64.uri_safe_alphabet public_key in
  of_uri (Uri.make ~scheme:"tilde" ~host:domain ~path ~query:[public_key,[]] ())

let public_key uri =
  match Uri.query uri with
  | [key, []] when String.length key = 43 ->
    Base64.decode ~alphabet:Base64.uri_safe_alphabet key
  | _ -> assert false
