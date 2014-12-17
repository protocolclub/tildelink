type t = {
  host : string;
  port : int;
}

let to_string { host; port } = Printf.sprintf "%s:%d" host port
