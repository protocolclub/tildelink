(** Tilde service endpoints. *)

(** The type of service endpoints. *)
type t = {
  host : string;
  port : int;
}

(** [to_string endp] converts [endp] to a [host:port] string representation. *)
val to_string : t -> string
