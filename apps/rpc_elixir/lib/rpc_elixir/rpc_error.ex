defmodule RpcElixir.RpcError do
  @moduledoc """
  Structured error returned from the dispatcher pipeline.
  `RpcElixir.Dispatcher` owns the promotion rules for typed handler errors.
  See [Handling errors](errors.md) for the guide.

  ## Wire contract

  Serialized to JSON as
  `{"code": string, "source"?: string, "message"?: string, "details"?: object}`.

  - `:code` — machine-readable atom. Required.
  - `:source` — coarse provenance category. Optional. See `t:source/0`.
  - `:message` — human-readable string. Optional but recommended.
  - `:details` — extra structured context. Optional.
  - `:status` — the HTTP status to return. Never serialized to the wire.
    Stamped by `framework/3`, or set by a handler returning a full
    `%RpcError{}`. Atom and map error returns leave it `nil`, and the
    transport then derives the status from `:code`.

  ## Framework codes

  `framework_errors/0` holds every framework code and its default status.
  `status_for/1` looks up one code. The transport layer reads these statuses.
  The dispatcher, plug, and resolution build framework errors via `framework/3`.

    * `:procedure_not_found` — no procedure registered for the requested path
    * `:input_validation_failed` — input did not match the procedure schema
    * `:output_validation_failed` — handler output failed the output schema
    * `:handler_error` — handler returned an unexpected value or raised
    * `:middleware_halted` — `Resolution.halt/2` was called with a
      non-`RpcError` reason. The original term is stored under `details.reason`.
    * `:unauthorized` — the caller is not authenticated (HTTP 401)
    * `:forbidden` — the caller is authenticated but lacks permission (HTTP 403)
    * `:payload_too_large` — body exceeded the configured byte cap
    * `:unsupported_media_type` — content-type was not `application/json`

  ## Client visibility

  A typed error's `:message` and `:details` are always serialized, by design.

  `:expose_error_details` redacts the diagnostic payload on three paths: a
  raised handler exception, a handler exception turned into a response, and a
  transport read-body failure. It removes the payload, not `:details` itself —
  `details.kind` is always sent.

  One case is never gated. When a handler returns `{:error, term}` for an
  unsupported `term`, `inspect(term)` is serialized under `details.reason`
  regardless of the flag. So never return an internal struct such as an
  `Ecto.Changeset` or a database error.
  """

  @typedoc """
  Coarse provenance category, paired with the fine-grained `:code`.

  `:code` alone cannot tell you the source. `:unauthorized` may be a middleware
  halt or a handler's typed error. So each layer stamps its own value:

    * `:framework` — built by `framework/3` (protocol, validation, transport)
    * `:middleware` — produced by `RpcElixir.Resolution.halt/2`
    * `:domain` — a typed `{:error, ...}` returned by a handler

  A caller may set `:source` on an `%RpcError{}` it builds. An explicit value is
  preserved, never overwritten. So the layer default applies only when `:source`
  is `nil`. See `Resolution.halt/2` and the dispatcher's typed-error promotion.

  By convention, `:transport` is reserved for client-synthesized failures
  (network, abort). It applies before any server envelope exists. Server code
  uses the other three.
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
  The default HTTP status for `code`. Returns `nil` for other codes, such as a
  user-defined typed error code.
  """
  @spec status_for(atom()) :: pos_integer() | nil
  def status_for(code), do: Map.get(@framework_errors, code)

  @doc """
  Builds a framework error. It stamps the default HTTP status for `code`. The
  status then travels with the error, instead of being re-derived downstream.
  It also tags `source: :framework`.
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
