# Plug options

`RpcElixir.Plug` mounts a router over HTTP. It reads seven options at `init/1`.
Only `:router` is required. The rest have safe defaults.

| Option | Default | What it does |
| --- | --- | --- |
| `:router` | required | The module that uses `RpcElixir.Router`. |
| `:path_prefix` | `"/rpc"` | Stripped from the request path before dispatch. |
| `:ctx_builder` | `nil` | Builds the base `RpcElixir.Context` from the conn. |
| `:max_body_size` | 8 MB (`8 * 1024 * 1024`) | Request body cap in bytes. |
| `:max_body_depth` | `64` | Nesting-depth cap on the decoded JSON body. |
| `:require_content_type` | `true` | Requires `content-type: application/json`. |
| `:allowed_origins` | `nil` (disabled) | Allow-list of origin strings. |

## `:path_prefix`

The plug only answers `POST`. The path must start with the prefix and a slash.
The rest of the path is the wire name. So `POST /rpc/users.get` dispatches the
procedure `"users.get"`. An empty remainder returns the not-found error. Any
other path returns it too.

## `:require_content_type`

Every request must carry `content-type: application/json`. The media type is
compared without case. Parameters such as a charset are allowed. A wrong type
or a missing header is rejected with `unsupported_media_type` at status 415.

**Turning this off removes the main CSRF defence.** The header requirement stops
the request being a simple cross-site request. Browsers must then send a CORS
preflight, which this plug never approves. HTML forms cannot send
`application/json` at all. Setting this to `false` removes that defence. You
then need another one in its place. A token check or a strict
`:allowed_origins` list are the usual choices.

The bundled JavaScript client always sends the header. A hand-written `curl` or
`fetch` call that omits it will fail with 415.

## `:allowed_origins`

This is an allow-list and it is disabled by default. When you pass a list, the
plug reads the `origin` request header. A request with no `origin` header
passes. Otherwise the first header value must appear in your list. The match
is an exact string compare. A value outside the list is rejected with
`forbidden` at status 403. Its `details.reason` is `"forbidden_origin"`. There
is no wildcard and no pattern matching.

## `:max_body_size` and `:max_body_depth`

Both are denial-of-service limits. The body is read in 1 MB chunks. A large
request never lands in memory at once. Exceeding the byte cap returns
`payload_too_large` at status 413.

The depth cap runs right after decoding. It bounds the stack and CPU that the
byte cap alone cannot. A body deeper than the cap returns
`input_validation_failed` at status 400. Its `details.reason` is
`"body_too_deep"`. The body must also decode to a JSON object. An empty body
counts as `{}`. See [Handling errors](errors.md) for the full code table.

## `:ctx_builder`

The builder is a `(Plug.Conn.t() -> RpcElixir.Context.t())` function. Its
result becomes the base context. The transport then always overwrites `:req`
with conn metadata. The `conn` and `socket` fields stay `nil` unless your
builder sets them. See [Writing middleware](middleware.md) for what to do
with the context.

## Session integration

`Plug.Session` and a session fetch must run before this plug. Order matters.

```elixir
defmodule MyApp.Router do
  use Plug.Builder

  plug Plug.Session,
    store: :cookie, key: "_my_app_session", signing_salt: "my_salt"

  plug :fetch_session
  plug RpcElixir.Plug, router: MyApp.RpcRouter
end
```

The plug reads the session into `ctx.req.session`. Middleware writes it back
through `RpcElixir.Resolution`. An unfetched session reads as an empty map
instead of `nil`.

## The `:expose_error_details` application key

This one is application config, not a plug option. Set it under the
`:elixir_ts_rpc` application. It defaults to `false`.

```elixir
config :elixir_ts_rpc, expose_error_details: true
```

When it is `false`, crash details and body-read failures are withheld from the
response. Keep it `false` in production. See [Handling errors](errors.md) for the
error shape rules.
