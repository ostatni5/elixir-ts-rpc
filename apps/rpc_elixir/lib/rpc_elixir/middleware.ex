defmodule RpcElixir.Middleware do
  @moduledoc """
  Behaviour for procedure middleware.

  A middleware transforms a `%RpcElixir.Resolution{}` and returns one. The
  chain runs in order, before input validation and the handler. A middleware
  can halt, but it cannot see the handler's result. See `c:call/2`.

  ## Declaring middleware

      procedure "users.update", &Hello.Users.update/2,
        middleware: [
          MyApp.Middleware.RequireUser,
          {RpcElixir.Middleware.Assign, source: :api}
        ]

  Each entry is a module or a `{module, opts}` tuple. Bare modules receive `[]`.

  ## Field ownership

  Middleware must **not** write to `:result`. The dispatcher owns that field.
  Use `Resolution.halt/2` to short-circuit with an error.

  ## Implementing a middleware

  Pass an `%RpcElixir.RpcError{}` to `RpcElixir.Resolution.halt/2` when the
  code matters. A bare term becomes `:middleware_halted` at status 500, and
  the term lands under `details.reason`.

      defmodule MyApp.Middleware.RequireUser do
        @behaviour RpcElixir.Middleware

        @impl true
        def call(%RpcElixir.Resolution{} = res, _opts) do
          case res.ctx.assigns[:current_user] do
            nil ->
              RpcElixir.Resolution.halt(res, %RpcElixir.RpcError{code: :unauthorized})

            _user ->
              res
          end
        end

        @impl true
        def rpc_error_codes(_opts), do: [:unauthorized]
      end
  """

  alias RpcElixir.Resolution

  @type opts :: term()

  @doc """
  Receives the resolution and this middleware's `opts`. Returns a resolution.

  Read or update `ctx` with `RpcElixir.Resolution.assign/3` or
  `RpcElixir.Resolution.put_ctx/3`. Set response cookies, headers, and session
  entries with the `resp_*` helpers. Call `RpcElixir.Resolution.halt/2` to skip
  the remaining middleware and the handler. Returning the resolution unchanged
  is also fine.

  `RpcElixir.Resolution.put_private/3` writes the resolution's own `:private`
  map. Handlers do not receive it. Use `assign/3` for anything a handler reads.

  Never write `:result` yourself. The handler step clobbers it and logs a
  warning.
  """
  @callback call(Resolution.t(), opts()) :: Resolution.t()

  @doc """
  Declares the error codes this middleware may pass to `Resolution.halt/2`.

  Codegen folds them into the error type of every procedure it wraps. The
  generated TypeScript error type and the runtime `.isError` codes both pick
  them up. So the client sees a cross-cutting code like `:unauthorized`, even
  when no handler `@spec` mentions it. Optional — a middleware that does not
  implement it contributes no codes. `opts` lets the code set depend on
  configuration.

      @impl true
      def rpc_error_codes(_opts), do: [:unauthorized]
  """
  @callback rpc_error_codes(opts()) :: [atom()]

  @optional_callbacks rpc_error_codes: 1
end
