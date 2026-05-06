defmodule RpcElixir.CodegenFixtures.Handlers do
  @moduledoc false

  @doc "Fetch a user by id."
  @spec get_user(%{required(:id) => String.t(), optional(:include_deleted) => boolean()}, %{}) ::
          {:ok, %{id: String.t(), name: String.t(), score: float()}}
          | {:error, :not_found | :forbidden}
  def get_user(_input, _ctx), do: {:ok, %{id: "1", name: "Alice", score: 1.0}}

  @spec list_active(%{}, %{}) :: {:ok, [%{id: String.t()}]}
  def list_active(_input, _ctx), do: {:ok, []}

  @spec create(%{name: String.t(), role: :admin | :member | :viewer}, %{}) ::
          {:ok, %{id: String.t()}} | {:error, :conflict}
  def create(_input, _ctx), do: {:ok, %{id: "new"}}
end

defmodule RpcElixir.CodegenFixtures.WeirdHandlers do
  @moduledoc false

  @spec call(
          %{
            optional(:"weird-key") => String.t(),
            optional(:"@type") => String.t(),
            optional(:"0start") => String.t(),
            optional(:normal) => String.t()
          },
          %{}
        ) :: {:ok, %{}}
  def call(_input, _ctx), do: {:ok, %{}}
end

defmodule RpcElixir.CodegenFixtures.DocSanitizeHandlers do
  @moduledoc false

  @doc "Proc with */ in its description"
  @spec call(%{}, %{}) :: {:ok, %{}}
  def call(_input, _ctx), do: {:ok, %{}}
end

# FooHandlers and BarHandlers intentionally share the same function name (`get_user`)
# so that routers combining both trigger the name-collision path in the codegen.
defmodule RpcElixir.CodegenFixtures.FooHandlers do
  @moduledoc false

  @spec get_user(%{id: String.t()}, %{}) :: {:ok, %{id: String.t()}}
  def get_user(_input, _ctx), do: {:ok, %{id: "1"}}
end

defmodule RpcElixir.CodegenFixtures.BarHandlers do
  @moduledoc false

  @spec get_user(%{id: String.t()}, %{}) :: {:ok, %{id: String.t()}}
  def get_user(_input, _ctx), do: {:ok, %{id: "1"}}
end

defmodule RpcElixir.CodegenFixtures.WrappedEnumHandlers do
  @moduledoc false

  # error type is nullable-wrapped enum: (nil | :conflict | :duplicate)
  @spec call(%{}, %{}) :: {:ok, %{}} | {:error, nil | :conflict | :duplicate}
  def call(_input, _ctx), do: {:ok, %{}}
end

defmodule RpcElixir.CodegenFixtures.UnionListHandlers do
  @moduledoc false

  @spec call(%{}, %{}) :: {:ok, %{items: [String.t() | nil]}}
  def call(_input, _ctx), do: {:ok, %{items: []}}
end

defmodule RpcElixir.CodegenFixtures.BrandedCustomHandlers do
  @moduledoc false
  alias RpcElixir.TypespecFixtures.Int64

  @spec call(%{id: Int64.t()}, %{}) :: {:ok, %{id: Int64.t()}}
  def call(%{id: id}, _ctx), do: {:ok, %{id: id}}
end

defmodule RpcElixir.CodegenFixtures.DupBrandHandlers do
  @moduledoc false
  alias RpcElixir.TypespecFixtures.{DupBrandA, DupBrandB}

  @spec call(%{a: DupBrandA.t(), b: DupBrandB.t()}, %{}) :: {:ok, %{}}
  def call(_input, _ctx), do: {:ok, %{}}
end

defmodule RpcElixir.CodegenFixtures.ReservedBrandHandlers do
  @moduledoc false
  alias RpcElixir.TypespecFixtures.ReservedBrand

  @spec call(%{id: ReservedBrand.t()}, %{}) :: {:ok, %{}}
  def call(_input, _ctx), do: {:ok, %{}}
end

defmodule RpcElixir.CodegenFixtures.StructClashHandlers do
  @moduledoc false
  alias RpcElixir.TypespecFixtures.{Product, StructClashBrand}

  @spec call(%{id: StructClashBrand.t()}, %{}) :: {:ok, %{product: Product.t()}}
  def call(_input, _ctx), do: {:ok, %{product: %Product{}}}
end

defmodule RpcElixir.CodegenFixtures.BadIdentifierHandlers do
  @moduledoc false
  alias RpcElixir.TypespecFixtures.BadIdentifierBrand

  @spec call(%{id: BadIdentifierBrand.t()}, %{}) :: {:ok, %{}}
  def call(_input, _ctx), do: {:ok, %{}}
end

defmodule RpcElixir.CodegenFixtures.NonStringHandlers do
  @moduledoc false
  alias RpcElixir.TypespecFixtures.NonStringBrand

  @spec call(%{id: NonStringBrand.t()}, %{}) :: {:ok, %{}}
  def call(_input, _ctx), do: {:ok, %{}}
end

defmodule RpcElixir.CodegenFixtures.NonStringWireHandlers do
  @moduledoc false
  alias RpcElixir.TypespecFixtures.NonStringWireBrand

  @spec call(%{id: NonStringWireBrand.t()}, %{}) :: {:ok, %{}}
  def call(_input, _ctx), do: {:ok, %{}}
end

defmodule RpcElixir.CodegenFixtures.BoolWireHandlers do
  @moduledoc false
  alias RpcElixir.TypespecFixtures.BoolWireBrand

  @spec call(%{id: BoolWireBrand.t()}, %{}) :: {:ok, %{}}
  def call(_input, _ctx), do: {:ok, %{}}
end

defmodule RpcElixir.CodegenFixtures.ReservedWordHandlers do
  @moduledoc false
  alias RpcElixir.TypespecFixtures.ReservedWordBrand

  @spec call(%{id: ReservedWordBrand.t()}, %{}) :: {:ok, %{}}
  def call(_input, _ctx), do: {:ok, %{}}
end

defmodule RpcElixir.CodegenFixtures.TwoDistinctBrandHandlers do
  @moduledoc false
  alias RpcElixir.TypespecFixtures.{Int64, Sku}

  @spec call(%{a: Int64.t(), b: Sku.t()}, %{}) :: {:ok, %{}}
  def call(_input, _ctx), do: {:ok, %{}}
end

defmodule RpcElixir.CodegenFixtures.BrandInListHandlers do
  @moduledoc false
  alias RpcElixir.TypespecFixtures.Int64

  @spec call(%{}, %{}) :: {:ok, %{ids: [Int64.t()]}}
  def call(_input, _ctx), do: {:ok, %{ids: []}}
end

defmodule RpcElixir.CodegenFixtures.EctoTimestampHandlers do
  @moduledoc false
  alias RpcElixir.TypespecFixtures.TimestampedSchema

  @spec call(%{}, %{}) :: {:ok, %{row: TimestampedSchema.t()}}
  def call(_input, _ctx), do: {:ok, %{row: %TimestampedSchema{}}}
end

defmodule RpcElixir.CodegenFixtures.AliasedDateHandlers do
  @moduledoc false

  @spec call(%{when: Date.t()}, %{}) :: {:ok, %{}}
  def call(_input, _ctx), do: {:ok, %{}}
end

defmodule RpcElixir.CodegenFixtures.WrappedDateTimeHandlers do
  @moduledoc false

  @spec call(
          %{
            required(:many) => [DateTime.t()],
            required(:maybe) => DateTime.t() | nil,
            optional(:lazy) => DateTime.t()
          },
          %{}
        ) :: {:ok, %{}}
  def call(_input, _ctx), do: {:ok, %{}}
end

defmodule RpcElixir.CodegenFixtures.MultiAliasHandlers do
  @moduledoc false

  @spec call(%{at: DateTime.t(), day: Date.t()}, %{}) :: {:ok, %{}}
  def call(_input, _ctx), do: {:ok, %{}}
end

defmodule RpcElixir.CodegenFixtures.UnixMillisInputHandlers do
  @moduledoc false

  @spec call(%{at: DateTime.t()}, %{}) :: {:ok, %{echoed: DateTime.t()}}
  def call(%{at: at}, _ctx) do
    if pid = Process.get(:received_input_sink), do: send(pid, {:handler_received, at})
    {:ok, %{echoed: at}}
  end
end

defmodule RpcElixir.CodegenFixtures.FloatWireHandlers do
  @moduledoc false
  alias RpcElixir.TypespecFixtures.FloatWireBrand

  @spec call(%{lat: FloatWireBrand.t()}, %{}) :: {:ok, %{}}
  def call(_input, _ctx), do: {:ok, %{}}
end

defmodule RpcElixir.CodegenFixtures.StructuralNameHandlers do
  @moduledoc false
  alias RpcElixir.TypespecFixtures.StructuralNameBrand

  @spec call(%{id: StructuralNameBrand.t()}, %{}) :: {:ok, %{}}
  def call(_input, _ctx), do: {:ok, %{}}
end

defmodule RpcElixir.CodegenFixtures.RecursiveTreeHandlers do
  @moduledoc false
  alias RpcElixir.TypespecFixtures.TreeNode

  @spec call(%{}, %{}) :: {:ok, TreeNode.t()}
  def call(_input, _ctx), do: {:ok, %TreeNode{label: "root", children: []}}
end

defmodule RpcElixir.CodegenFixtures.MutuallyRecursiveHandlers do
  @moduledoc false
  alias RpcElixir.TypespecFixtures.GraphNodeA

  @spec call(%{}, %{}) :: {:ok, GraphNodeA.t()}
  def call(_input, _ctx), do: {:ok, %GraphNodeA{value: 1, next: nil}}
end

defmodule RpcElixir.CodegenFixtures.CodeWithDetailsHandlers do
  @moduledoc false

  @spec call(%{}, %{}) ::
          {:ok, %{}}
          | {:error, %{code: :rate_limited | :quota_exceeded, retry_after: integer()}}
  def call(_input, _ctx), do: {:ok, %{}}
end
