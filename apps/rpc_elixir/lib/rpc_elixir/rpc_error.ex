defmodule RpcElixir.RpcError do
  @moduledoc """
  Structured error returned from the dispatcher pipeline.

  ## Wire contract

  Serialized to JSON as
  `{"code": string, "source"?: string, "message"?: string, "details"?: object}`.

  - `:code` is a machine-readable atom. Required.
  - `:source` is the coarse provenance category (see `t:source/0`). Optional.
  - `:message` is a human-readable string. Optional but recommended.
  - `:details` is any extra structured context. Optional.
  - `:status` is the HTTP status to return. Set by typed handler errors and
    framework errors, not serialized to the wire.

  ## Typed handler errors

  When a handler's `@spec` declares `{:error, atom_union()}` or
  `{:error, %{code: atom_union(), message: String.t(), ...}}`, the dispatcher
  promotes that return value to a top-level `RpcError`:

    - `{:error, :not_found}` →
      `%RpcError{code: :not_found, message: "not_found", details: nil}`

    - `{:error, %{code: :not_found, message: "user X", field: "id"}}` →
      `%RpcError{code: :not_found, message: "user X", details: %{field: "id"}}`

  The `:code` and `:message` keys are pulled to the top level. Everything else
  flows through `:details`. This matches the JS `Error` contract on the
  TypeScript client (`err.message` is populated for stack traces and logging).

  ## Framework codes

  Framework error codes and their default HTTP statuses are the single source
  of truth defined in `@framework_errors` (see `framework_errors/0` and
  `status_for/1`). The transport layer reads these statuses. The dispatcher,
  plug, and resolution build framework errors via `framework/3`.

    * `:procedure_not_found`, no procedure registered for the requested path
    * `:input_validation_failed`, request input did not match the procedure schema
    * `:output_validation_failed`, handler returned a value that failed output schema
    * `:handler_error`, handler returned an unexpected value or raised
    * `:middleware_halted`, `Resolution.halt/2` was called with a non-`RpcError`
      reason. The original term is stored under `details.reason`
    * `:unauthorized`, the caller is not authenticated (HTTP 401)
    * `:forbidden`, the caller is authenticated but lacks permission (HTTP 403)
    * `:payload_too_large`, request body exceeded the configured byte cap
    * `:unsupported_media_type`, request content-type was not `application/json`

  ## Client visibility

  Note: a typed error's `:message` and `:details` are always serialized to the
  client by design (see `RpcElixir.Dispatcher`). Framework `:details` are gated
  behind `:expose_error_details` for the internal exception/return paths, but
  typed handler-error payloads are intentionally exposed.
  """

  @typedoc """
  Coarse provenance category, paired with the fine-grained `:code`.

  Cannot be inferred from `:code` alone (e.g. `:unauthorized` may be a middleware halt
  *or* a handler's typed error), so it is stamped at the layer that builds the
  error:

    * `:framework`, built by `framework/3` (protocol/validation/transport-layer)
    * `:middleware`, produced by `RpcElixir.Resolution.halt/2`
    * `:domain`, a typed `{:error, ...}` returned by a handler

  A caller that constructs its own `%RpcError{}` may set `:source` explicitly. An
  explicit value is preserved rather than overwritten (see `Resolution.halt/2`
  and the dispatcher's typed-error promotion), so the layer default only applies
  when `:source` is `nil`.

  `:transport` is, by convention, reserved for failures the *client* synthesizes
  (network/abort) before any server envelope exists. Server code uses the other
  three.
  """
  @type source :: :transport | :framework | :middleware | :domain

  @typedoc "Machine-readable framework error code."
  @type framework_code ::
          :procedure_not_found
          | :input_validation_failed
          | :output_validation_failed
          | :handler_error
          | :middleware_halted
          | :unauthorized
          | :forbidden
          | :payload_too_large
          | :unsupported_media_type

  @type t :: %__MODULE__{
          code: atom(),
          message: String.t() | nil,
          details: map() | nil,
          status: pos_integer() | nil,
          source: source() | nil
        }

  defstruct [:code, :message, :status, :details, :source]

  # Single source of truth: framework error code → default HTTP status.
  # The transport's status mapping and every framework-error constructor read
  # from here, so a new code cannot silently fall through to a generic status.
  @framework_errors %{
    procedure_not_found: 404,
    input_validation_failed: 400,
    output_validation_failed: 500,
    handler_error: 500,
    middleware_halted: 500,
    unauthorized: 401,
    forbidden: 403,
    payload_too_large: 413,
    unsupported_media_type: 415
  }

  @doc "The framework error code → default HTTP status map."
  @spec framework_errors() :: %{framework_code() => pos_integer()}
  def framework_errors, do: @framework_errors

  @doc """
  The default HTTP status for `code`, or `nil` when `code` is not a known
  framework code (e.g. a user-defined typed error code).
  """
  @spec status_for(atom()) :: pos_integer() | nil
  def status_for(code), do: Map.get(@framework_errors, code)

  @doc """
  Builds a framework error, stamping the default HTTP status for `code` so the
  status travels with the error rather than being re-derived downstream, and
  tagging `source: :framework`.
  """
  @spec framework(framework_code(), String.t() | nil, map() | nil) :: t()
  def framework(code, message, details \\ nil) when is_map_key(@framework_errors, code) do
    %__MODULE__{
      code: code,
      message: message,
      details: details,
      status: @framework_errors[code],
      source: :framework
    }
  end
end
