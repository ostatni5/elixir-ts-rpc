defmodule RpcElixir.TypespecFixtures.Product do
  @moduledoc false
  defstruct [:id, :name]
  @type t :: %__MODULE__{id: integer(), name: String.t()}
end

defmodule RpcElixir.TypespecFixtures.StringAlias do
  @moduledoc false
  @type t :: String.t()
end

defmodule RpcElixir.TypespecFixtures.Empty do
  @moduledoc false
end

defmodule RpcElixir.TypespecFixtures.Tree do
  @moduledoc false
  defstruct [:value, :children]
  @type t :: %__MODULE__{value: integer(), children: [t()]}
end

defmodule RpcElixir.TypespecFixtures.Handlers do
  @moduledoc "Compiled handlers used to exercise RpcElixir.Types.FromSpec."

  @type id :: integer()
  @type user :: %{id: id(), name: String.t()}

  @spec get_user(%{id: id()}, %{}) :: {:ok, user()} | {:error, :not_found}
  def get_user(%{id: id}, _ctx), do: {:ok, %{id: id, name: "alice"}}

  @spec list_users(%{limit: integer()}, %{}) :: {:ok, [user()]}
  def list_users(%{limit: _}, _ctx), do: {:ok, []}

  @spec echo(a, %{}) :: {:ok, a} when a: String.t()
  def echo(a, _ctx), do: {:ok, a}

  @spec chained(a, %{}) :: {:ok, a} when a: b, b: integer()
  def chained(a, _ctx), do: {:ok, a}

  @spec status(%{}, %{}) :: :ok | :error
  def status(_params, _ctx), do: :ok

  # ctx typed as the non-wire `%RpcElixir.Context{}` struct: it carries
  # `Plug.Conn.t()`/`socket: struct()`, so it must never be walked as a wire type.
  @spec with_struct_ctx(%{}, RpcElixir.Context.t()) :: {:ok, %{}}
  def with_struct_ctx(_input, _ctx), do: {:ok, %{}}

  def no_spec(input, _ctx), do: {:ok, input}
end

defmodule RpcElixir.TypespecFixtures.Inferred do
  @moduledoc """
  Exercises `RpcElixir.Types.FromInferred` against signatures recovered solely
  by Elixir's set-theoretic type inference, without any `@spec` annotations.

  Deliberately uses different function names from `Handlers` (e.g. `find_user`,
  `tagged_status`, `wrapped_get` instead of `chained`, `status`) so that
  inferred-spec extraction is tested independently of the explicit-spec fixture
  rather than as a parallel mirror of it.
  """

  def get_user(%{id: id}, _ctx), do: {:ok, %{id: id, name: "alice"}}

  def list_users(%{limit: _}, _ctx), do: {:ok, []}

  def echo(a, _ctx) when is_binary(a), do: {:ok, a}

  def no_spec(input, _ctx), do: {:ok, input}

  defp build_user(id), do: %{id: id, name: "alice"}

  def find_user(%{id: id}, _ctx) do
    if id > 0 do
      {:ok, build_user(id)}
    else
      {:error, :not_found}
    end
  end

  def tagged_status(%{status: s}, _ctx) when s in [:active, :idle] do
    {:ok, s}
  end

  def tagged_status(_, _ctx), do: {:error, :unknown}

  def wrapped_get(params, ctx), do: find_user(params, ctx)
end

defmodule RpcElixir.TypespecFixtures.FakeSchema do
  @moduledoc "Real Ecto schema covering every field type the walker maps."
  use Ecto.Schema

  @primary_key false
  schema "fake" do
    field(:id, :id)
    field(:name, :string)
    field(:score, :integer)
    field(:weight, :float)
    field(:active, :boolean)
    field(:birthday, :date)
    field(:created_at_usec, :utc_datetime_usec)
    field(:created_at, :utc_datetime)
    field(:updated_local, :naive_datetime)
    field(:updated_local_usec, :naive_datetime_usec)
    field(:start_time, :time)
    field(:balance, :decimal)
    field(:uuid, :binary_id)
    field(:tags, {:array, :string})
  end
end

defmodule RpcElixir.TypespecFixtures.TimestampedSchema do
  @moduledoc "Minimal Ecto schema with a single `:utc_datetime` field for wire-alias regression tests."
  use Ecto.Schema

  @primary_key false
  schema "timestamped" do
    field(:created_at, :utc_datetime)
  end
end

defmodule RpcElixir.TypespecFixtures.RejectedMapSchema do
  @moduledoc "Ecto schema with a `:map` field — rejected by the walker."
  use Ecto.Schema

  @primary_key false
  schema "rejected" do
    field(:meta, :map)
  end
end

defmodule RpcElixir.TypespecFixtures.Money do
  @moduledoc false
  @behaviour RpcElixir.CustomType

  defstruct [:amount, :currency]
  @type t :: %__MODULE__{amount: integer(), currency: String.t()}

  @impl RpcElixir.CustomType
  def wire_spec, do: %{kind: "primitive", type: "string"}

  @impl RpcElixir.CustomType
  def serialize(%__MODULE__{amount: a, currency: c}), do: "#{a} #{c}"
end

defmodule RpcElixir.TypespecFixtures.Int64 do
  @moduledoc false
  @behaviour RpcElixir.CustomType

  @type t :: integer()

  @impl RpcElixir.CustomType
  def wire_spec, do: %{kind: "primitive", type: "string"}

  @impl RpcElixir.CustomType
  def serialize(int) when is_integer(int), do: Integer.to_string(int)

  @impl RpcElixir.CustomType
  def ts_type, do: "Int64String"
end

defmodule RpcElixir.TypespecFixtures.DupBrandA do
  @moduledoc false
  @behaviour RpcElixir.CustomType
  @type t :: integer()
  @impl true
  def wire_spec, do: %{kind: "primitive", type: "string"}
  @impl true
  def serialize(v), do: to_string(v)
  @impl true
  def ts_type, do: "DupBrand"
end

defmodule RpcElixir.TypespecFixtures.DupBrandB do
  @moduledoc false
  @behaviour RpcElixir.CustomType
  @type t :: integer()
  @impl true
  def wire_spec, do: %{kind: "primitive", type: "string"}
  @impl true
  def serialize(v), do: to_string(v)
  @impl true
  def ts_type, do: "DupBrand"
end

defmodule RpcElixir.TypespecFixtures.ReservedBrand do
  @moduledoc false
  @behaviour RpcElixir.CustomType
  @type t :: integer()
  @impl true
  def wire_spec, do: %{kind: "primitive", type: "string"}
  @impl true
  def serialize(v), do: to_string(v)
  @impl true
  def ts_type, do: "DecimalString"
end

defmodule RpcElixir.TypespecFixtures.StructClashBrand do
  @moduledoc false
  @behaviour RpcElixir.CustomType
  @type t :: integer()
  @impl true
  def wire_spec, do: %{kind: "primitive", type: "string"}
  @impl true
  def serialize(v), do: to_string(v)
  @impl true
  def ts_type, do: "Product"
end

defmodule RpcElixir.TypespecFixtures.BadIdentifierBrand do
  @moduledoc false
  @behaviour RpcElixir.CustomType
  @type t :: integer()
  @impl true
  def wire_spec, do: %{kind: "primitive", type: "string"}
  @impl true
  def serialize(v), do: to_string(v)
  @impl true
  def ts_type, do: "Bad Name"
end

defmodule RpcElixir.TypespecFixtures.NonStringBrand do
  @moduledoc false
  @behaviour RpcElixir.CustomType
  @type t :: integer()
  @impl true
  def wire_spec, do: %{kind: "primitive", type: "string"}
  @impl true
  def serialize(v), do: to_string(v)
  @impl true
  def ts_type, do: :not_a_string
end

defmodule RpcElixir.TypespecFixtures.NonStringWireBrand do
  @moduledoc false
  @behaviour RpcElixir.CustomType
  @type t :: integer()
  @impl true
  def wire_spec, do: %{kind: "primitive", type: "integer"}
  @impl true
  def serialize(v), do: v
  @impl true
  def ts_type, do: "IntWire"
end

defmodule RpcElixir.TypespecFixtures.BoolWireBrand do
  @moduledoc false
  @behaviour RpcElixir.CustomType
  @type t :: boolean()
  @impl true
  def wire_spec, do: %{kind: "primitive", type: "boolean"}
  @impl true
  def serialize(v), do: v
  @impl true
  def ts_type, do: "BoolWire"
end

defmodule RpcElixir.TypespecFixtures.ReservedWordBrand do
  @moduledoc false
  @behaviour RpcElixir.CustomType
  @type t :: integer()
  @impl true
  def wire_spec, do: %{kind: "primitive", type: "string"}
  @impl true
  def serialize(v), do: to_string(v)
  @impl true
  def ts_type, do: "Date"
end

defmodule RpcElixir.TypespecFixtures.Sku do
  @moduledoc false
  @behaviour RpcElixir.CustomType
  @type t :: String.t()
  @impl true
  def wire_spec, do: %{kind: "primitive", type: "string"}
  @impl true
  def serialize(v), do: to_string(v)
  @impl true
  def ts_type, do: "Sku"
end

defmodule RpcElixir.TypespecFixtures.StructuralNameBrand do
  @moduledoc false
  @behaviour RpcElixir.CustomType
  @type t :: integer()
  @impl true
  def wire_spec, do: %{kind: "primitive", type: "string"}
  @impl true
  def serialize(v), do: to_string(v)
  @impl true
  def ts_type, do: "RpcClient"
end

defmodule RpcElixir.TypespecFixtures.FloatWireBrand do
  @moduledoc false
  @behaviour RpcElixir.CustomType
  @type t :: float()
  @impl true
  def wire_spec, do: %{kind: "primitive", type: "float"}
  @impl true
  def serialize(v) when is_float(v), do: v
  @impl true
  def ts_type, do: "Latitude"
end

defmodule RpcElixir.TypespecFixtures.TreeNode do
  @moduledoc false
  defstruct [:label, :children]
  @type t :: %__MODULE__{label: String.t(), children: [t()]}
end

defmodule RpcElixir.TypespecFixtures.OrgUnit do
  @moduledoc false
  defstruct [:name, :parent]
  @type t :: %__MODULE__{name: String.t(), parent: RpcElixir.TypespecFixtures.OrgUnit.t() | nil}
end

defmodule RpcElixir.TypespecFixtures.GraphNodeA do
  @moduledoc false
  defstruct [:value, :next]
  @type t :: %__MODULE__{value: integer(), next: RpcElixir.TypespecFixtures.GraphNodeB.t() | nil}
end

defmodule RpcElixir.TypespecFixtures.GraphNodeB do
  @moduledoc false
  defstruct [:label, :prev]
  @type t :: %__MODULE__{label: String.t(), prev: RpcElixir.TypespecFixtures.GraphNodeA.t() | nil}
end

defmodule RpcElixir.TypespecFixtures.DeserializingId do
  @moduledoc false
  @behaviour RpcElixir.CustomType
  @type t :: integer()
  @impl true
  def wire_spec, do: %{kind: "primitive", type: "string"}
  @impl true
  def serialize(int) when is_integer(int), do: Integer.to_string(int)

  @impl true
  def deserialize(wire) when is_binary(wire) do
    case Integer.parse(wire) do
      {int, ""} -> {:ok, int}
      _ -> {:error, "not an integer id"}
    end
  end
end
