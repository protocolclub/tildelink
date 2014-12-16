(** [tilde://] URI validator *)

(** A valid [tilde://] URI *)
type t

(** [of_uri uri] validates [uri] as a [tilde://] URI or returns
    an error. *)
val of_uri : Uri.t -> [ `Ok of t | `Error of string ]

(** [to_uri turi] returns an [Uri.t] corresponding to [tilde://] URI
    [turi]. *)
val to_uri : t -> Uri.t

(** [make ~domain ~path ~public_key] creates a [tilde://] URI from
    its components. *)
val make : domain:string -> path:string -> public_key:string ->
           [ `Ok of t | `Error of string ]

(** [public_key turi] returns a raw Curve25519 public key, extracted
    from [turi]. *)
val public_key : t -> string
