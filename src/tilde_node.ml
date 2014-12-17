type service = {
  expires   : float option;
  endpoints : Tilde_endpoint.t list;
}

type t = {
  router    : [`Router] Lwt_zmq.Socket.t;
  services  : (Tilde_uri.t, service) Hashtbl.t;
}

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
    let services = Hashtbl.create 16 in
    Hashtbl.add services uri { expires = None; endpoints = [()] };
    Lwt.return { router = Lwt_zmq.Socket.of_socket router; services; }
  end

let services { services } = services

let make_ok value =
  `Assoc ["ok", value]

let make_error code msg =
  `Assoc ["error", `Assoc ["code", `String code; "message", `String msg]]

let make_endpoints =
  List.map (fun x -> `String (Tilde_endpoint.to_string x))

module J = Yojson.Basic

let do_node request router =
  let domain = ZMQ.Socket.get_identity (Lwt_zmq.Socket.to_socket router) in
  make_ok (`Assoc ["domain", `String domain])

let do_list services =
  services |>
  CCHashtbl.to_list |>
  List.map (fun (uri, {endpoints}) ->
    Tilde_uri.to_string uri, `List (make_endpoints endpoints)) |>
  fun xs -> make_ok (`Assoc xs)

let do_discover json services =
  match J.Util.(json |> member "uri" |> to_string) |> Tilde_uri.of_string with
  | `Error msg -> make_error "protocol-error" ("URI: " ^ msg)
  | `Ok uri ->
    match CCHashtbl.get services uri with
    | None -> make_error "not-found" ("Service " ^ Tilde_uri.to_string uri ^ " is not registered")
    | Some { endpoints } ->
      make_ok (`List (make_endpoints endpoints))

let string_of_id (id:Lwt_zmq.Socket.Router.id_t) =
  let id = (id :> string) in
  if id.[0] = '\x00' then Base64.encode id else String.escaped id

let rec handle ({ router; services } as node) id request =
  let reply json =
    let reply = J.to_string json in
    Lwt_log.debug_f ~section "%s: send %s" (string_of_id id) reply >>
    Lwt_zmq.Socket.Router.send router id [""; reply] >>
    listen node
  in
  try%lwt
    let json = J.from_string request in
    match J.Util.(member "command" json |> to_string) with
    | "info" -> reply (do_node json router)
    | "list" -> reply (do_list services)
    | "discover" -> reply (do_discover json services)
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
    listen node

and listen ({ router; services } as node) =
  match%lwt Lwt_zmq.Socket.Router.recv router with
  | id, [""; msg] ->
    Lwt_log.debug_f ~section "%s: recv %s" (string_of_id id) msg >>
    handle node id msg
  | id, _ ->
    Lwt_log.warning_f ~section "%s: malformed message" (string_of_id id) >>
    (* Drop it. *)
    listen node
