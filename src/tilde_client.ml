type t = [`Req] Lwt_zmq.Socket.t

type node_info = {
  node_domain : string;
}

type 'a result = ('a, string * string) CCError.t

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

let roundtrip request parse socket =
  let json = J.to_string request in
  Lwt_log.debug_f ~section "send: %s" json >>
  Lwt_zmq.Socket.send_all socket [json] >>
  match%lwt Lwt_zmq.Socket.recv_all socket with
  | [json] ->
    Lwt_log.debug_f ~section "recv: %s" json >>
    begin try%lwt
      match J.from_string json with
      | `Assoc ["ok", result] ->
        parse result
      | `Assoc ["error", descr] ->
        let code, msg = J.Util.(descr |> member "code" |> to_string,
                                descr |> member "message" |> to_string) in
        Lwt_log.info_f ~section "error %s: %s" code msg >>
        Lwt.return (`Error (code, msg))
      | _ ->
        Lwt.return (`Error ("protocol-error",
                            "Top-level object should contain only \"ok\" or \"error\""))
    with
    | J.Util.Type_error (msg, json)
    | J.Util.Undefined (msg, json) ->
      Lwt.return (`Error ("protocol-error", (msg ^ " in " ^ (Yojson.Basic.to_string json))))
    | Failure msg ->
      Lwt.return (`Error ("protocol-error", msg))
    end
  | _ -> assert false

let node_info =
  roundtrip (make_cmd "node-info" []) (fun reply ->
    Lwt.return (`Ok { node_domain = J.Util.(reply |> member "domain" |> to_string) }))

let endpoints_of_json json =
  J.Util.(json |> to_list) |> List.map (fun json ->
    let host, port =
      J.Util.(json |> member "host" |> to_string,
              json |> member "port" |> to_int)
    in
    Tilde_endpoint.{ host; port })

let service_list =
  roundtrip (make_cmd "service-list" []) (fun reply ->
    J.Util.(to_assoc reply) |>
    List.map (fun (uri, endpoints) ->
      match Tilde_uri.of_string uri with
      | `Error err -> failwith err
      | `Ok uri -> uri, endpoints_of_json endpoints) |>
    fun result -> Lwt.return (`Ok result))

let discover uri =
  let args = ["uri", `String (Tilde_uri.to_string uri)] in
  roundtrip (make_cmd "discover" args) (fun reply ->
    Lwt.return (`Ok (endpoints_of_json reply)))
