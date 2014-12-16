(* open Lwt.Infix *)
let (>>=), (>>|) = Lwt.(>>=), Lwt.(>|=)

let zmq =
  let ctx = ZMQ.Context.create () in
  ZMQ.Context.set_ipv6 ctx true;
  ctx

let lookup host port =
  match%lwt Lwt_unix.getaddrinfo host port [] with
  | {Lwt_unix.ai_addr = Lwt_unix.ADDR_INET (inet_addr, port)} :: _ ->
    Lwt.return (inet_addr, port)
  | _ -> assert false

let node host port domain =
  let%lwt inet_addr, port = lookup host port in
  let server = ZMQ.Socket.create zmq ZMQ.Socket.rep in
  ZMQ.Socket.bind server (Printf.sprintf "tcp://%s:%d" (Unix.string_of_inet_addr inet_addr) port);
  Lwt.return (`Ok ())

open Cmdliner

let host_arg =
  Arg.(required & opt (some string) None &
       info ["h"; "host"] ~docv:"HOST" ~doc:"Hostname")

let bind_address_arg =
  Arg.(value & opt string "localhost" &
       info ["b"; "bind-to"] ~docv:"BIND-TO" ~doc:"Bind to address")

let port_arg ~doc =
  Arg.(value & opt string (string_of_int 0x7e7e) &
       info ["p"; "port"] ~docv:"PORT" ~doc)

let domain_arg =
  Arg.(required & pos 0 (some string) None &
       info [] ~docv:"DOMAIN" ~doc:"The tildelink domain this node serves")

let run x = Term.(ret (pure Lwt_main.run $ x))

let node_cmd =
  let doc = "run a tildelink discovery node" in
  run Term.(pure node $ bind_address_arg $ port_arg ~doc:"Bind to port" $ domain_arg),
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
