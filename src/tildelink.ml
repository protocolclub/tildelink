(* open Lwt.Infix *)
let (>>=), (>>|) = Lwt.(>>=), Lwt.(>|=)

let return_ok x = Lwt.return (`Ok x)
let return_error x = Lwt.return (`Error (false, x))

let zmq =
  let ctx = ZMQ.Context.create () in
  ZMQ.Context.set_ipv6 ctx true;
  ctx

let lookup host port =
  match%lwt Lwt_unix.getaddrinfo host (string_of_int port) [] with
  | {Lwt_unix.ai_addr = Lwt_unix.ADDR_INET (inet_addr, port)} :: _ ->
    Lwt.return (Unix.string_of_inet_addr inet_addr, port)
  | [] -> Lwt.fail (Failure (Printf.sprintf "Cannot look up endpoint %s:%d" host port))
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

let run_node identity host port domain =
  let%lwt host, port = lookup host port in
  let%lwt keypair    = load_identity identity in
  let%lwt node = Tilde_node.create ~keypair ~domain ~host ~port zmq in
  Tilde_node.listen node

let client identity uri port =
  let%lwt keypair = load_identity identity in
  Tilde_client.create ~keypair ~uri ~port zmq

let run_node_info client =
  match%lwt Tilde_client.node_info client with
  | `Ok { Tilde_client.node_domain } ->
    Lwt_io.printlf "Domain: %s" node_domain >>
    return_ok ()
  | `Error (code, msg) -> return_error msg

let run_list client =
  match%lwt Tilde_client.service_list client with
  | `Ok services ->
    Lwt_io.printl "Services:" >>= fun () ->
    services |> List.map fst |> List.map Tilde_uri.to_string |>
    Lwt_list.iter_s (Lwt_io.printlf " * %s") >>
    return_ok ()
  | `Error (code, msg) -> return_error msg

let run_discover uri client =
  match%lwt Tilde_client.discover uri client with
  | `Ok endpoints ->
    Lwt_io.printl "Endpoints:" >>= fun () ->
    endpoints |> List.map Tilde_endpoint.to_string |>
    Lwt_list.iter_s (Lwt_io.printlf " * %s") >>
    return_ok ()
  | `Error (code, msg) -> return_error msg

(* ----------------------------------------------------------- CLI ARGUMENTS *)

open Cmdliner

let sdocs = "COMMON OPTIONS"

let tilde_uri =
  (fun str -> Tilde_uri.of_uri (Uri.of_string str)),
  (fun fmt uri -> Format.fprintf fmt "%a" Tilde_uri.pp uri)

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
  Arg.(value & opt int 0x7e7e &
       info ["p"; "port"] ~docv:"PORT" ~doc)

let domain_arg =
  Arg.(required & pos 0 (some string) None &
       info [] ~docv:"DOMAIN" ~doc:"The tildelink domain this node serves.")

let rec try_read files =
  match files with
  | [] -> None
  | file :: files ->
    try
      let content = CCOpt.get_exn (CCIO.read_line (open_in file)) in
      match Tilde_uri.of_uri (Uri.of_string content) with
      | `Ok uri -> Some uri
      | `Error msg -> failwith (file ^ ": " ^ msg)
    with
    | Sys_error _ -> try_read files

let discovery_uri_arg =
  let default_uri =
    try_read ["/etc/tildelink-uri";
              Filename.concat (Sys.getenv "HOME") ".tildelink-uri"]
  in
  Arg.(required & opt (some tilde_uri) default_uri &
       info ["discovery"] ~docv:"URI"
            ~doc:"The tilde:// URI of the discovery service. \
                  By default, taken from ~/.tildelink-uri and /etc/tildelink-uri in that order.")

let service_uri_arg =
  Arg.(required & pos 0 (some tilde_uri) None &
       info [] ~docv:"URI" ~doc:"The tilde:// URI of the target service.")

(* ------------------------------------------------ CMDLINER-LWT INTEGRATION *)

let run thread =
  let catch_lwt thread =
    Lwt_main.run (
      try%lwt
        thread
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

(* ----------------------------------------------------- HIGH-LEVEL COMMANDS *)

let docs = "HIGH-LEVEL COMMANDS"

let node_cmd =
  let doc = "run a tildelink discovery node" in
  run Term.(pure run_node $ identity_arg $ bind_address_arg
                          $ port_arg ~doc:"Socket binding port." $ domain_arg),
  Term.info "node" ~doc ~docs ~sdocs

let client_term =
  Term.(pure client $ identity_arg $ discovery_uri_arg $ port_arg ~doc:"Discovery service port.")

(* ---------------------------------------------------- EXPLORATORY COMMANDS *)

let docs = "EXPLORATORY COMMANDS"

let node_info_cmd =
  let doc = "print information about a tildelink discovery node" in
  run Term.(pure Lwt.bind $ client_term $ pure run_node_info),
  Term.info "node-info" ~doc ~docs ~sdocs

let service_list_cmd =
  let doc = "print service list" in
  run Term.(pure (fun client -> client >>= run_list)
                 $ client_term),
  Term.info "service-list" ~doc ~docs ~sdocs

let discover_cmd =
  let doc = "print service endpoints" in
  run Term.(pure (fun uri client -> client >>= run_discover uri)
                 $ service_uri_arg $ client_term),
  Term.info "discover" ~doc ~docs ~sdocs

(* -------------------------------------------------------------- CLI SETUP *)

let default_cmd =
  let doc = "a distributed service discovery mechanism" in
  let man = [
    `S "BUGS";
    `P "File bug reports at https://github.com/protocolclub/tildelink/issues.";
  ] in
  Term.(ret (pure (`Help (`Pager, None)))),
  Term.info "tildelink" ~version:"0.1" ~doc ~man ~sdocs

let () =
  let services = [
    node_cmd;
    node_info_cmd; service_list_cmd; discover_cmd
  ] in
  match Term.eval_choice default_cmd services with
  | `Error _ -> exit 1
  | _ -> exit 0
