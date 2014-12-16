type t = [`Router] Lwt_zmq.Socket.t

let section = Lwt_log.Section.make "node"

let create ~keypair:(public_key,secret_key) ~domain ~host ~port zmq =
  let router = ZMQ.Socket.create zmq ZMQ.Socket.router in
  begin%lwt
    ZMQ.Socket.set_linger_period router 0;
    ZMQ.Socket.set_identity router domain;
    ZMQ.Socket.set_curve_server router true;
    ZMQ.Socket.set_curve_secretkey router secret_key;
    ZMQ.Socket.set_router_mandatory router true; (* for debugging *)
    let listen_uri = Printf.sprintf "tcp://%s:%d" host port in
    ZMQ.Socket.bind router listen_uri;
    Lwt_log.info_f ~section "listening on %s" listen_uri >>
    let uri = CCError.get_exn (Tilde_uri.make ~domain ~path:"/" ~public_key) in
    Lwt_log.notice_f ~section "node %s created" (Tilde_uri.to_string uri) >>
    Lwt.return (Lwt_zmq.Socket.of_socket router)
  end

let make_ok value =
  `Assoc ["ok", value]

let make_error code msg =
  `Assoc ["error", `Assoc ["code", `String code; "message", `String msg]]

module J = Yojson.Basic

let string_of_id (id:Lwt_zmq.Socket.Router.id_t) =
  let id = (id :> string) in
  if id.[0] = '\x00' then Base64.encode id else String.escaped id

let rec handle router id request =
  let reply json =
    let reply = J.to_string json in
    Lwt_log.debug_f ~section "%s: send %s" (string_of_id id) reply >>
    Lwt_zmq.Socket.Router.send router id [""; reply] >>
    listen router
  in
  try%lwt
    let json = J.from_string request in
    match J.Util.(member "command" json |> to_string) with
    | "info" ->
      let domain = ZMQ.Socket.get_identity (Lwt_zmq.Socket.to_socket router) in
      reply (make_ok (`Assoc ["domain", `String domain]))
    | cmd ->
      reply (make_error "unknown-command" ("Unknown command " ^ cmd))
  with
  | J.Util.Type_error (msg, json)
  | J.Util.Undefined (msg, json) ->
    reply (make_error "protocol-error" (msg ^ " in " ^ (Yojson.Basic.to_string json)))
  | Failure msg ->
    reply (make_error "protocol-error" msg)
  | exn ->
    Lwt_log.error_f ~section ~exn "%s: exception" (string_of_id id) >>
    listen router

and listen router =
  match%lwt Lwt_zmq.Socket.Router.recv router with
  | id, [""; msg] ->
    Lwt_log.debug_f ~section "%s: recv %s" (string_of_id id) msg >>
    handle router id msg
  | id, _ ->
    Lwt_log.warning_f ~section "%s: malformed message" (string_of_id id) >>
    (* Drop it. *)
    listen router
