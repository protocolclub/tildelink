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

(** The type of request results. The error is comprised of [code, message]. *)
type 'a result = ('a, string * string) CCError.t

(** [node_info client] returns information about the node [client]
    is connected to. *)
val node_info : t -> node_info result Lwt.t

(** [service_list client] returns the list of all services registered
    at the node [client] is connected to.  *)
val service_list : t -> (Tilde_uri.t * Tilde_endpoint.t list) list result Lwt.t

(** [discover] returns the list of endpoints corresponding to the service,
    if one is registered at the node [client] is connected to. *)
val discover : Tilde_uri.t -> t -> Tilde_endpoint.t list result Lwt.t
