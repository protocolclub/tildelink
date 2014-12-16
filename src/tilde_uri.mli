(** [tilde://] URI validator *)

(** A valid [tilde://] URI *)
type t

(** [of_uri uri] validates [uri] as a [tilde://] URI or returns
    an error. *)
val of_uri : Uri.t -> [ `Ok of t | `Error of string ]

(** [to_uri uri] returns an [Uri.t] corresponding to [tilde://] URI
    [uri]. *)
val to_uri : t -> Uri.t

(** [to_string uri] converts the [tilde://] URI [uri] to a string. *)
val to_string : t -> string

(** [pp fmt uri] pretty-prints the [tilde://] URI [uri]. *)
val pp : Format.formatter -> t -> unit

(** [make ~domain ~path ~public_key] creates a [tilde://] URI from
    its components. *)
val make : domain:string -> path:string -> public_key:string ->
           [ `Ok of t | `Error of string ]

(** [domain uri] returns the domain, extracted from [uri]. *)
val domain : t -> string

(** [path uri] returns the path, extracted from [uri]. *)
val path : t -> string

(** [public_key uri] returns the Curve25519 public key in raw form,
    extracted from [uri]. *)
val public_key : t -> string
