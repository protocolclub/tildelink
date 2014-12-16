(* open Lwt.Infix *)
let (>>=), (>>|) = Lwt.(>>=), Lwt.(>|=)

let zmq =
  let ctx = ZMQ.Context.create () in
  ZMQ.Context.set_ipv6 ctx true;
  ctx

let lookup host port =
  match%lwt Lwt_unix.getaddrinfo host port [] with
  | {Lwt_unix.ai_addr = Lwt_unix.ADDR_INET (inet_addr, port)} :: _ ->
    Lwt.return (Unix.string_of_inet_addr inet_addr, port)
  | [] -> Lwt.fail (Failure (Printf.sprintf "Cannot look up endpoint %s:%s" host port))
  | _ -> assert false

let load_identity file =
  let alphabet, pad = Base64.uri_safe_alphabet, false in
  if Sys.file_exists file then
    let%lwt input = Lwt_io.open_file ~mode:Lwt_io.input file in
    match%lwt Lwt_stream.to_list (Lwt_io.read_lines input) with
    | [pub; sec] ->
      Lwt_io.close input >>
      Lwt.return (Base64.(decode ~alphabet pub, decode ~alphabet sec))
    | _ -> Lwt.fail (Failure ("Cannot decode identity file " ^ file))
  else
    let pub, sec = ZMQ.Curve.keypair () |> CCPair.map_same ZMQ.Z85.decode in
    let%lwt output = Lwt_io.open_file ~mode:Lwt_io.output file in
    Lwt_unix.chmod file 0o600 >>
    Lwt_io.write_lines output
      (Lwt_stream.of_list Base64.[encode ~alphabet ~pad pub; encode ~alphabet ~pad sec]) >>
    Lwt_io.close output >>
    Lwt.return (pub, sec)

let node host port identity domain =
  let%lwt host, port = lookup host port in
  let%lwt keypair    = load_identity identity in
  let%lwt node = Tilde_node.create ~keypair ~domain ~host ~port zmq in
  Tilde_node.listen node

open Cmdliner

let identity = ()

let identity_arg =
  Arg.(value & opt string (Filename.concat (Sys.getenv "HOME") ".tildelink-secret") &
       info ["i"; "identity"] ~docv:"IDENTITY-FILE"
            ~doc:"Curve25519 keypair file. \
                  The keypair file contains two URI-safe base64-encoded lines, \
                  containing the public and the secret key. \
                  It is created if nonexistent.")

let host_arg =
  Arg.(value & opt string "localhost" &
       info ["h"; "host"] ~docv:"HOST" ~doc:"Hostname")

let bind_address_arg =
  Arg.(value & opt string "localhost" &
       info ["b"; "bind-to"] ~docv:"BIND-TO" ~doc:"Socket binding address.")

let port_arg ~doc =
  Arg.(value & opt string (string_of_int 0x7e7e) &
       info ["p"; "port"] ~docv:"PORT" ~doc)

let domain_arg =
  Arg.(required & pos 0 (some string) None &
       info [] ~docv:"DOMAIN" ~doc:"The tildelink domain this node serves.")

let run thread =
  let catch_lwt thread =
    Lwt_main.run (
      try%lwt
        thread >> Lwt.return (`Ok ())
      with
      | Failure err ->
        Lwt.return (`Error (false, err))
      | Unix.Unix_error (err, syscall, filename) ->
        let msg =
          if filename = "" then Printf.sprintf "%s: %s" syscall (Unix.error_message err)
          else Printf.sprintf "%s: %s: %s" syscall filename (Unix.error_message err)
        in
        Lwt.return (`Error (false, msg)))
  in
  Term.(ret (pure catch_lwt $ thread))

let node_cmd =
  let doc = "run a tildelink discovery node" in
  run Term.(pure node $ bind_address_arg $ port_arg ~doc:"Socket binding port."
                      $ identity_arg $ domain_arg),
  Term.info "node" ~doc

let default_cmd =
  let doc = "a distributed service discovery mechanism" in
  let man = [
    `S "BUGS";
    `P "File bug reports at https://github.com/protocolclub/tildelink/issues.";
  ] in
  Term.(ret (pure (`Help (`Pager, None)))),
  Term.info "tildelink" ~version:"0.1" ~doc ~man

let () =
  match Term.eval_choice default_cmd [node_cmd] with
  | `Error _ -> exit 1
  | _ -> exit 0
