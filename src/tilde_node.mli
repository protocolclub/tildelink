(** Tildelink discovery node *)

(** The type of tildelink discovery nodes *)
type t

(** The type of tildelink service entries. *)
type service = {
  expires   : float option;
  endpoints : Tilde_endpoint.t list;
}

(** [create ~secret_key ~domain ~listen_uri zmq_context] creates a node
    listening at ZeroMQ URI [listen_uri]. *)
val create : keypair:string * string -> domain:string ->
             host:string -> port:int -> ZMQ.Context.t -> t Lwt.t

(** [listen node] returns a thread that answers messages and expires
    old entries. The thread never returns. *)
val listen : t -> 'a Lwt.t

(** [services node] returns a list of all services registered in [node]. *)
val services : t -> (Tilde_uri.t, service) Hashtbl.t
