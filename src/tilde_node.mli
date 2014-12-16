(** Tildelink discovery node *)

(** The type of tildelink discovery nodes *)
type t

(** [create ~secret_key ~domain ~listen_uri zmq_context] creates a node
    listening at ZeroMQ URI [listen_uri]. *)
val create : keypair:string * string -> domain:string ->
             host:string -> port:int -> ZMQ.Context.t -> t Lwt.t

(** [listen node] returns a thread that answers messages received
    by [node] forever. *)
val listen : t -> 'a Lwt.t
