# Writing middleware

Middleware runs before a procedure's handler. It can read the request. It can
stop the call. It can also write cookies, headers, and the session.

## The behaviour

A middleware is a module with two rules. It declares
`@behaviour RpcElixir.Middleware`. It implements `call/2`. The callback takes a
`%RpcElixir.Resolution{}` and this middleware's opts. It returns a resolution.

`rpc_error_codes/1` is the second callback. It is optional. It declares the
error codes this middleware may halt with.

```elixir
defmodule MyApp.Middleware.RequireUser do
  @behaviour RpcElixir.Middleware

  alias RpcElixir.{Resolution, RpcError}

  @impl true
  def call(%Resolution{} = res, _opts) do
    case res.ctx.req[:session]["user_id"] do
      nil -> Resolution.halt(res, %RpcError{code: :unauthorized})
      user_id -> Resolution.assign(res, :current_user_id, user_id)
    end
  end

  @impl true
  def rpc_error_codes(_opts), do: [:unauthorized]
end
```

## Registering middleware

Pass `:middleware` to `scope`, to `expose`, or to `procedure/3`. Each entry is a
module or a `{module, opts}` tuple. A bare module receives `[]` as its opts.

A scope around an `expose` is the usual shape. The chain covers every function
in the module:

```elixir
defmodule MyApp.RpcRouter do
  use RpcElixir.Router

  scope "public" do
    expose MyApp.Health
  end

  scope "users", middleware: [MyApp.Middleware.RequireUser] do
    expose MyApp.Users
  end
end
```

Since middleware applies to the whole module, the module is also the unit you
split along: one handler per auth level, and the scope says which. When a single
function needs its own chain, register that one with `procedure` instead:

```elixir
scope "users", middleware: [MyApp.Middleware.RequireUser] do
  procedure "list", &MyApp.Users.list/2

  procedure "update", &MyApp.Users.update/2,
    middleware: [{RpcElixir.Middleware.Assign, source: :api}]
end
```

**A plain Plug is not a middleware.** Registration is checked at compile time.
The module must export `call/2` and it must declare
`@behaviour RpcElixir.Middleware`. A Plug that happens to export `call/2` is
rejected on purpose. Missing either rule raises `CompileError` at the
registration site.

## Order

Scope middleware runs before procedure middleware. Scopes nest. Prefixes
concatenate and middleware accumulates outer to inner. The outermost entry runs
first.

The whole chain runs before input validation. That matters for auth. A
middleware can reject a call even when the input is invalid.

## Halting

Call `RpcElixir.Resolution.halt/2` to stop the pipeline. Remaining middleware
and the handler are skipped.

Pass an `%RpcError{}` when the code matters. Halting keeps that code and stamps
`source: :middleware`. Any other term becomes `:middleware_halted` with status
500. The term is stored under `details.reason`.

Never write `:result` yourself. The dispatcher owns that field. A direct write
is replaced by the handler step and logged as a warning.

## Typed error codes on the client

`rpc_error_codes/1` is the only way your codes reach the generated client.
Codegen collects the codes of every middleware on a procedure, in attach order,
and removes duplicates. It widens the procedure's error type with
`MiddlewareError<"unauthorized">`. The same codes join the runtime `.isError`
list.

Without `rpc_error_codes/1` the halt still works at runtime. The client just
cannot narrow on the code. See [Handling errors](errors.md) and
[Using the client](https://ostatni5.github.io/elixir-ts-rpc/guide/client).

## Passing data to the handler

`Resolution.assign/3` puts a value in `ctx.assigns`. That is how a middleware
hands data to a handler. Handlers read the context as their second argument.

`put_ctx/3` replaces a known field on the context struct. Unknown keys raise
`KeyError`. `put_private/3` writes the resolution's own `:private` map, for
framework data. Handlers never see it.

The context fields are `conn`, `socket`, `assigns`, `private`, and `req`. Two
details are easy to miss. `conn` and `socket` stay `nil` unless your
`:ctx_builder` fills them. Session keys are strings, so read
`ctx.req.session["user_id"]` and not an atom key.

## Writing to the HTTP response

Handlers cannot touch the HTTP response. Middleware can. Use
`put_resp_cookie/4`, `delete_resp_cookie/3`, and `put_resp_header/3`. For the
session use `put_session/3`, `delete_session/2`, or `clear_session/1`. The
transport applies them after dispatch.

A session write needs `Plug.Session` earlier in the pipeline. Without it the
write is dropped and a warning is logged. See
[Plug options](plug-options.md).

## The built-in Assign middleware

`RpcElixir.Middleware.Assign` puts static values into `ctx.assigns`. Register
it as `{RpcElixir.Middleware.Assign, source: :api, environment: :prod}`. Each
key and value in the opts becomes an assign. Existing keys are overwritten.
Non-atom keys raise `ArgumentError`.
