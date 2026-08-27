defmodule RpcElixir.Context do
  @moduledoc """
  Request-scoped context threaded through middleware and into handlers.

  The transport builds a `%Context{}` and passes it to the dispatcher.
  Middleware may read or augment it through the surrounding
  `%RpcElixir.Resolution{}`. Handlers receive the final context as their second
  argument.

  `RpcElixir.Plug` builds it from the optional `:ctx_builder` callback, then
  always overwrites `:req`. It never sets `:conn` or `:socket`. Those stay
  `nil` unless your own `:ctx_builder` fills them.

  ## The `:req` field

  The HTTP Plug transport fills `:req` with transport-level request metadata.
  In-process calls via `RpcElixir.call/4` leave it `nil`.

      %{
        cookies: %{String.t() => String.t()},   # parsed request cookies
        headers: [{String.t(), String.t()}],     # raw header list from the conn
        remote_ip: :inet.ip_address() | nil,     # client IP
        method: String.t(),                      # always "POST" for v1
        path: String.t(),                        # full request path, prefix included
        session: map()                          # string keys; empty map if the session was not fetched
      }

  Session keys are strings, because Plug normalizes them. Read them as
  `ctx.req.session["user_id"]`, not `ctx.req.session[:user_id]`.
  """

  @typedoc "Transport-level request metadata, populated by the Plug adapter."
  @type req :: %{
          cookies: %{optional(String.t()) => String.t()},
          headers: [{String.t(), String.t()}],
          remote_ip: :inet.ip_address() | nil,
          method: String.t(),
          path: String.t(),
          session: map()
        }

  @typedoc "Request-scoped context struct."
  @type t :: %__MODULE__{
          conn: Plug.Conn.t() | nil,
          socket: struct() | nil,
          assigns: map(),
          private: map(),
          req: req() | nil
        }

  defstruct conn: nil, socket: nil, assigns: %{}, private: %{}, req: nil
end
