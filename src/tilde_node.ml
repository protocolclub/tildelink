type t = [`Router] Lwt_zmq.Socket.t

let section = Lwt_log.Section.make "node"

let create ~keypair:(secret_key,public_key) ~domain ~host ~port zmq =
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
    let uri = Uri.with_port (Tilde_uri.to_uri uri) (Some port) in
    Lwt_log.notice_f ~section "node %s created" (Uri.to_string uri) >>
    Lwt.return (Lwt_zmq.Socket.of_socket router)
  end

let make_ok value =
  `Assoc ["ok", value]

let make_error code msg =
  `Assoc ["error", `Assoc ["code", `String code; "message", `String msg]]

module J = Yojson.Basic
module Ju = J.Util

let rec handle router id msg =
  let reply json =
    let reply = J.to_string json in
    Lwt_log.debug_f ~section "%S: send %s" id reply >>
    listen router
  in
  try%lwt
    let json = J.from_string msg in
    match Ju.(member "command" json |> to_string) with
    | "info" ->
      let domain = ZMQ.Socket.get_identity (Lwt_zmq.Socket.to_socket router) in
      reply (make_ok (`Assoc ["domain", `String domain]))
    | cmd ->
      reply (make_error "unknown-command" ("Unknown command " ^ cmd))
  with
  | Ju.Type_error (msg, json)
  | Ju.Undefined (msg, json) ->
    reply (make_error "protocol-error" (msg ^ " in " ^ (Yojson.Basic.to_string json)))
  | Failure msg ->
    reply (make_error "protocol-error" msg)
  | exn ->
    Lwt_log.error_f ~section ~exn "%S: exception" id >>
    listen router

and listen router =
  match%lwt Lwt_zmq.Socket.recv_all router with
  | id :: "" :: msg :: [] ->
    Lwt_log.debug_f ~section "%S: recv %s" id msg >>
    handle router id msg
  | id :: "" :: _ ->
    Lwt_log.warning_f ~section "%S: malformed message" id >>
    (* Drop it. *)
    listen router
  | _ -> assert false
