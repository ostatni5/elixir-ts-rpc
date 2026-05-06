defmodule RpcElixir.Context do
  @moduledoc """
  Request-scoped context threaded through middleware and into handlers.

  The transport layer (Plug, Channels) builds a `%Context{}` from the
  authentication mechanism it uses and hands it to the dispatcher.
  Middleware may read or augment the context via the surrounding
  `%RpcElixir.Resolution{}`. Handlers receive the final context as their
  second argument (after the input).

  ## The `:req` field

  When a request arrives via the HTTP Plug transport, `:req` is populated with
  a plain map carrying transport-level request metadata:

      %{
        cookies: %{String.t() => String.t()},   # parsed request cookies
        headers: [{String.t(), String.t()}],     # raw header list from the conn
        remote_ip: :inet.ip_address() | nil,     # client IP
        method: String.t(),                      # always "POST" for v1
        path: String.t(),                        # request path used for dispatch
        session: map()                          # session data, empty map if Plug.Session not configured
      }

  When called in-process via `RpcElixir.call/4`, `:req` is `nil`.
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
