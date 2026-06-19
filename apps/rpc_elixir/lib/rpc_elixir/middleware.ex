defmodule RpcElixir.Middleware do
  @moduledoc """
  Behaviour for procedure middleware.

  A middleware is a module that transforms a `%RpcElixir.Resolution{}` and
  returns a (possibly modified) resolution. Middleware compose around the
  dispatcher and may:

    * read or update `ctx` via `Resolution.put_ctx/3`, `Resolution.assign/3`,
      `Resolution.put_private/3`
    * halt the chain via `Resolution.halt/2`, which short-circuits remaining
      middleware and the handler
    * leave the resolution untouched

  ## Declaring middleware

  Middleware are attached to a procedure in the router DSL:

      procedure "users.update", &Hello.Users.update/2,
        middleware: [
          RpcElixir.Middleware.Assign,
          {RpcElixir.Middleware.Assign, key: :source, value: :api}
        ]

  Each entry is either a bare module or a `{module, opts}` tuple. Bare modules
  receive `[]` as `opts`.

  ## Field ownership

  Middleware must **not** write to `:result` directly, that field is owned by
  the dispatcher. Use `halt/2` to short-circuit with an error.

  ## Implementing a middleware

      defmodule MyApp.Middleware.RequireUser do
        @behaviour RpcElixir.Middleware

        @impl true
        def call(%RpcElixir.Resolution{ctx: %{user: nil}} = res, _opts) do
          RpcElixir.Resolution.halt(res, :unauthenticated)
        end

        def call(res, _opts), do: res
      end
  """

  alias RpcElixir.Resolution

  @type opts :: term()

  @callback call(Resolution.t(), opts()) :: Resolution.t()

  @doc """
  Declares the error codes this middleware may pass to `halt/2`, so codegen can
  fold them into the declared error type of every procedure the middleware wraps.

  This is what lets the generated client know a cross-cutting error like
  `:unauthorized` is possible on an endpoint even though no handler `@spec`
  mentions it. The procedure's generated TypeScript error type and its runtime
  `.isError` codes both pick these up. Optional, middleware that doesn't implement
  it contributes no codes (the codegen behaves exactly as before).

  Receives the middleware's `opts` so a code set can depend on configuration.

      @impl true
      def rpc_error_codes(_opts), do: [:unauthorized]
  """
  @callback rpc_error_codes(opts()) :: [atom()]

  @optional_callbacks rpc_error_codes: 1
end
