tildelink
=========

_tildelink_ is a distributed service discovery mechanism. The problem that
lead to the creation of _tildelink_ is: how do we allow people to discover
services without creating hierarchy or single points of failure?

More concretely, _tildelink_ is a distributed [ZeroMQ][]-based
key-value store that maps service names to ZeroMQ endpoints,
a daemon that implements this store, and a collection of tools
to establish connections from the command line.

[zeromq]: http://zeromq.org

Usage
-----

TODO

Installation
------------

_tildelink_ can be installed via [OPAM](https://opam.ocaml.org):

    opam pin add -y tildelink .

Architecture
------------

All communication in _tildelink_ is done via [ZeroMQ][].

The central concept of _tildelink_ is the notion of _service_.
A service is a collection of ZeroMQ endpoints and is identified
by a `tilde://` [URI][rfc3986]. The URI contains the [Curve25519][]
public key associated with the service; all communication is
encrypted.

The discovery service is just another _tildelink_ service.

[rfc3986]: https://tools.ietf.org/html/rfc3986
[reqrep]: http://rfc.zeromq.org/spec:28

### tilde:// URIs

A _tildelink_ URI is a [RFC3986][]-conformant URI. The schema
component must be `tilde`. The userinfo, port and fragment components
must be empty. The query fragment must contain a [Curve25519][]
public key, encoded using Base64 with URL- and filename-safe alphabet
(specified in [RFC4648][]). Since any 32 bytes constitute a valid
Curve25519 public key, no validation besides length is required.

The host component contains an arbitrary string that identifies
a node. The path component contains an arbitrary string starting
with `/` that identifies a service logically associated with a node;
by convention:

  * a path component equal to `/` identifies a discovery service;
  * all other path components should start with a path segment of
    the form `~user`, where `~user` is the name of the user who
    is maintaining the service; the rest of path segments are
    arbitrary.

[curve25519]: http://cr.yp.to/ecdh.html
[rfc4648]: https://tools.ietf.org/html/rfc4648#page-7

### Discovery service

The discovery service is a _tildelink_ service that performs two jobs:

  * it accepts registration and discovery requests from the clients
    wishing to use the network;
  * it disseminates the updated service mappings among the network.

The discovery service uses the [request-reply pattern][reqrep] and
JSON for serialization.

The requests are of the form `{"version": "<ver>", "command": "<cmd>", ..}`,
where `<cmd>` is the command name and `..` is command-specific fields.
The responses are either of the form `{"ok": ..}`, where `..`
is a command-specific value, or `{"error": {"code": "<code>", "message": "<msg>"}}`,
where `<code>` is a command-specific error code, and `<msg>` is
a human-readable error message.

Currently, `<ver>` is `1`. If the service is unable to recognize
the version, an error with code `unknown-version` is returned.

If the service is unable to parse JSON or required fields are missing,
an error with code `protocol-error` is returned.

[reqrep]: rfc.zeromq.org/spec:28

#### Node information

`{"version": 1, "command": "info"}`

`{"ok": {"domain": "<domain>"}}`

The node information command allows to request metadata from
the current node. Currently, only node domain is returned.

#### Service discovery

`{"version": 1, "command": "discover", "uri": "<uri>"}`

`{"ok": [["<host>", <port>], ..]}`

`{"error": {"code": "not-found", ..}}`

The service discovery command returns the list of endpoints
(host:port pairs) associated with the given service.

#### Service list

`{"version": 1, "command": "list"}`

`{"ok": {"<uri>": [["<host>", <port>], ..], ..}`

The service list command returns all registered services.

OCaml API
---------

The documentation for the OCaml API is available [online][gh-pages].

[gh-pages]: http://protocolclub.github.io/tildelink/

License
-------

_tildelink_ is distributed under the terms of [MIT license](LICENSE.txt).
