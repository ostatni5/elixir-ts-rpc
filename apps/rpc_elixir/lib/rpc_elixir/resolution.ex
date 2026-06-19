defmodule RpcElixir.Resolution do
  @moduledoc """
  Envelope threaded through the middleware pipeline for a single procedure
  invocation. Middleware receive and return a `%Resolution{}`.

  ## Field ownership

  Different fields have different writers, keeping the struct single but
  partitioning who touches what (mirroring `Plug.Conn`):

    * `:ctx`, middleware and the dispatcher both write. Use `put_ctx/3`,
      `assign/3` (application data), or `put_private/3` (framework data on
      the context). Read by handlers.
    * `:params`, `:private`, middleware-owned. Use `put_private/3` for
      framework-internal scratch data.
    * `:state`, set to `:halted` only via `halt/2`. Never set directly.
    * `:result`, **dispatcher-owned.** Middleware should not write to it
      directly. Use `halt/2` to short-circuit with an error. Direct writes
      pre-dispatch are clobbered by the handler step.
    * `:procedure`, set at construction time, never mutated.
    * `:resp_cookies`, middleware-writable. Use `put_resp_cookie/4` or
      `delete_resp_cookie/3`. The transport adapter drains this onto the
      response after dispatch. Format: `%{name => {value, opts}}` for set,
      `%{name => {:delete, opts}}` for delete.
    * `:resp_headers`, middleware-writable. Use `put_resp_header/3`. The
      transport adapter appends these to the response. Duplicates are allowed
      (e.g. multiple `Set-Cookie` values). Format: `[{name, value}]`.
    * `:resp_session`, middleware-writable. Use `put_session/3`,
      `delete_session/2`, or `clear_session/1`. The transport adapter drains
      this into the Plug session after dispatch. Requires `Plug.Session` to be
      configured earlier in the pipeline.

  ## Halting

  Calling `halt/2` short-circuits remaining middleware and the handler. The
  dispatcher returns the resolution unchanged from that point.
  """

  alias RpcElixir.{Context, RpcError}

  @typedoc "Pipeline execution state."
  @type state :: :continue | :halted

  @typedoc "Cookie entry in resp_cookies, either a set or delete instruction."
  @type resp_cookie_entry :: {String.t(), keyword()} | {:delete, keyword()}

  @typedoc "Session entry in resp_session, either a value to set or `:delete`."
  @type resp_session_entry :: term() | :delete

  @typedoc "Resolution envelope."
  @type t :: %__MODULE__{
          ctx: Context.t(),
          params: map(),
          state: state(),
          result: {:ok, term()} | {:error, RpcError.t()} | nil,
          private: map(),
          procedure: String.t() | nil,
          resp_cookies: %{optional(String.t()) => resp_cookie_entry()},
          resp_headers: [{String.t(), String.t()}],
          resp_session: %{optional(term()) => resp_session_entry()},
          resp_session_clear: boolean()
        }

  @enforce_keys [:procedure]
  defstruct ctx: %Context{},
            params: %{},
            state: :continue,
            result: nil,
            private: %{},
            procedure: nil,
            resp_cookies: %{},
            resp_headers: [],
            resp_session: %{},
            resp_session_clear: false

  @doc """
  Halts the pipeline with an error.

  Accepts either a fully-formed `%RpcError{}` or any other term, which is
  wrapped under `code: :middleware_halted` with the original term stored at
  `details.reason`. After halting, downstream middleware and the handler are
  skipped.
  """
  @spec halt(t(), RpcError.t() | term()) :: t()
  def halt(%__MODULE__{} = res, %RpcError{} = err) do
    %{res | state: :halted, result: {:error, %{err | source: err.source || :middleware}}}
  end

  def halt(%__MODULE__{} = res, reason) do
    err =
      RpcError.framework(:middleware_halted, "middleware halted the pipeline", %{reason: reason})

    halt(res, %{err | source: :middleware})
  end

  @doc """
  Replaces a known field on the nested `%Context{}` struct.

  Raises `KeyError` if `key` is not a field on the context struct. To store
  arbitrary request-scoped data, use `assign/3` (application data) or
  `put_private/3` (framework/library data) instead.
  """
  @spec put_ctx(t(), atom(), term()) :: t()
  def put_ctx(%__MODULE__{ctx: ctx} = res, key, value) do
    %{res | ctx: Map.replace!(ctx, key, value)}
  end

  @doc """
  Stores framework/library-private request-scoped data under `key` in the
  resolution's `:private` map. For application data, use `assign/3` instead.
  """
  @spec put_private(t(), atom(), term()) :: t()
  def put_private(%__MODULE__{private: private} = res, key, value) do
    %{res | private: Map.put(private, key, value)}
  end

  @doc """
  Stores application data under `key` in the context's `:assigns` map, the
  primary way middleware passes request-scoped data to handlers.
  """
  @spec assign(t(), atom(), term()) :: t()
  def assign(%__MODULE__{} = res, key, value) do
    update_in(res, [Access.key!(:ctx), Access.key!(:assigns)], &Map.put(&1, key, value))
  end

  @doc """
  Stores a cookie to be set on the response.

  `opts` are forwarded directly to `Plug.Conn.put_resp_cookie/4` by the
  transport adapter. Supported options include `:http_only`, `:secure`,
  `:same_site`, `:max_age`, `:path`, `:domain`, `:sign`, `:encrypt`.

  Safe to call from middleware.
  """
  @spec put_resp_cookie(t(), String.t(), String.t(), keyword()) :: t()
  def put_resp_cookie(%__MODULE__{resp_cookies: cookies} = res, name, value, opts \\ []) do
    %{res | resp_cookies: Map.put(cookies, name, {value, opts})}
  end

  @doc """
  Marks a cookie for deletion on the response.

  `opts` are forwarded to `Plug.Conn.delete_resp_cookie/3` by the transport
  adapter.

  Safe to call from middleware.
  """
  @spec delete_resp_cookie(t(), String.t(), keyword()) :: t()
  def delete_resp_cookie(%__MODULE__{resp_cookies: cookies} = res, name, opts \\ []) do
    %{res | resp_cookies: Map.put(cookies, name, {:delete, opts})}
  end

  @doc """
  Appends a response header. Duplicates are preserved (useful for headers like
  `set-cookie` that must be set separately per cookie).

  Safe to call from middleware.
  """
  @spec put_resp_header(t(), String.t(), String.t()) :: t()
  def put_resp_header(%__MODULE__{resp_headers: headers} = res, name, value) do
    %{res | resp_headers: headers ++ [{name, value}]}
  end

  @doc """
  Stores a session key-value pair to be set on the response.

  Requires `Plug.Session` to be configured in the Plug pipeline. The transport
  adapter drains this into the session after dispatch.

  Safe to call from middleware.
  """
  @spec put_session(t(), term(), term()) :: t()
  def put_session(%__MODULE__{resp_session: session} = res, key, value) do
    %{res | resp_session: Map.put(session, key, value)}
  end

  @doc """
  Marks a session key for deletion on the response.

  Safe to call from middleware.
  """
  @spec delete_session(t(), term()) :: t()
  def delete_session(%__MODULE__{resp_session: session} = res, key) do
    %{res | resp_session: Map.put(session, key, :delete)}
  end

  @doc """
  Marks the entire session to be cleared on the response.

  The transport adapter calls `Plug.Conn.clear_session/1` when it encounters
  this sentinel. Any other `resp_session` entries are ignored after a clear.

  Safe to call from middleware.
  """
  @spec clear_session(t()) :: t()
  def clear_session(%__MODULE__{} = res) do
    %{res | resp_session_clear: true}
  end
end
