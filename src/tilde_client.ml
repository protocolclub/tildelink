type t = [`Req] Lwt_zmq.Socket.t

type node_info = {
  node_domain : string;
}

let section = Lwt_log.Section.make "discovery"

let create ~keypair:(public_key,secret_key) ~uri ~port zmq =
  let req = ZMQ.Socket.create zmq ZMQ.Socket.req in
  begin%lwt
    ZMQ.Socket.set_linger_period req 0;
    ZMQ.Socket.set_curve_server req false;
    ZMQ.Socket.set_curve_secretkey req secret_key;
    ZMQ.Socket.set_curve_publickey req public_key;
    ZMQ.Socket.set_curve_serverkey req (Tilde_uri.public_key uri);
    let connect_uri = Printf.sprintf "tcp://%s:%d" (Tilde_uri.domain uri) port in
    ZMQ.Socket.connect req connect_uri;
    Lwt_log.info_f ~section "connecting to %s" connect_uri >>
    Lwt.return (Lwt_zmq.Socket.of_socket req)
  end

module J = Yojson.Basic

let make_cmd name fields =
  `Assoc (("command", `String name) :: fields)

let roundtrip json parse req =
  let msg = J.to_string json in
  Lwt_log.debug_f ~section "send: %s" msg >>
  Lwt_zmq.Socket.send_all req [msg] >>
  match%lwt Lwt_zmq.Socket.recv_all req with
  | [msg] ->
    Lwt_log.debug_f ~section "recv: %s" msg >>
    begin try%lwt
      match J.from_string msg with
      | `Assoc ["ok", result] ->
        parse result
      | `Assoc ["error", descr] ->
        let code, msg = J.Util.(descr |> member "code" |> to_string,
                                descr |> member "message" |> to_string) in
        Lwt_log.info_f ~section "error %s: %s" code msg >>
        Lwt.return (`Error (code, msg))
      | _ ->
        Lwt.return (`Error ("protocol-error", "Malformed reply"))
    with
    | J.Util.Type_error (msg, json)
    | J.Util.Undefined (msg, json) ->
      Lwt.return (`Error ("protocol-error", (msg ^ " in " ^ (Yojson.Basic.to_string json))))
    | Failure msg ->
      Lwt.return (`Error ("protocol-error", msg))
    end
  | _ -> assert false

let node_info =
  roundtrip (make_cmd "info" []) (fun result ->
    Lwt.return (`Ok { node_domain = J.Util.(result |> member "domain" |> to_string) }))
