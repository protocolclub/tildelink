(** Tildelink discovery client *)

(** The type of tildelink discovery clients. *)
type t

(** [create uri] creates a client with local identity [keypair]
    and discovery service URI [uri]. As [tilde://] URIs may not
    contain the port, it is provided separately. *)
val create : keypair:string * string -> uri:Tilde_uri.t ->
             port:int -> ZMQ.Context.t -> t Lwt.t

(** The type of discovery node information. *)
type node_info = {
  node_domain : string;
}

(** [node_info client] returns information about the node the client
    is connected to. *)
val node_info : t -> (node_info, string * string) CCError.t Lwt.t
