defmodule RpcElixir.CodegenTest.Router do
  @moduledoc false
  use RpcElixir.Router
  alias RpcElixir.ManifestFixtures.Handlers

  procedure "users.get", &Handlers.get_user/2
  procedure "users.list", &Handlers.list_users/2
  procedure "users.create", &Handlers.create_user/2
end

defmodule RpcElixir.CodegenTest.WeirdRouter do
  @moduledoc false
  use RpcElixir.Router
  alias RpcElixir.CodegenFixtures.WeirdHandlers

  procedure "props.call", &WeirdHandlers.call/2
end

defmodule RpcElixir.CodegenTest.DocSanitizeRouter do
  @moduledoc false
  use RpcElixir.Router
  alias RpcElixir.CodegenFixtures.DocSanitizeHandlers

  procedure "doc.call", &DocSanitizeHandlers.call/2
end

defmodule RpcElixir.CodegenTest.FooRouter do
  @moduledoc false
  use RpcElixir.Router
  alias RpcElixir.CodegenFixtures.FooHandlers

  procedure "foo.get", &FooHandlers.get_user/2
end

defmodule RpcElixir.CodegenTest.BarRouter do
  @moduledoc false
  use RpcElixir.Router
  alias RpcElixir.CodegenFixtures.BarHandlers

  procedure "bar.get", &BarHandlers.get_user/2
end

defmodule RpcElixir.CodegenTest.CollisionRouter do
  @moduledoc false
  use RpcElixir.Router
  alias RpcElixir.CodegenFixtures.BarHandlers
  alias RpcElixir.CodegenFixtures.FooHandlers

  procedure "foo.get2", &FooHandlers.get_user/2
  procedure "bar.get2", &BarHandlers.get_user/2
end

defmodule RpcElixir.CodegenTest.CombinedRouter do
  @moduledoc false
  use RpcElixir.Router
  alias RpcElixir.CodegenFixtures.BarHandlers
  alias RpcElixir.CodegenFixtures.FooHandlers

  procedure "foo.get", &FooHandlers.get_user/2
  procedure "bar.get", &BarHandlers.get_user/2
end

defmodule RpcElixir.CodegenTest.PingRouter do
  @moduledoc false
  use RpcElixir.Router
  alias RpcElixir.CodegenFixtures.Handlers

  procedure "ping", &Handlers.list_active/2
end

defmodule RpcElixir.CodegenTest.DeepRouter do
  @moduledoc false
  use RpcElixir.Router
  alias RpcElixir.CodegenFixtures.Handlers

  procedure "users.profile.update", &Handlers.get_user/2
end

defmodule RpcElixir.CodegenTest.SiblingRouter do
  @moduledoc false
  use RpcElixir.Router
  alias RpcElixir.CodegenFixtures.BarHandlers
  alias RpcElixir.CodegenFixtures.FooHandlers

  procedure "users.get", &FooHandlers.get_user/2
  procedure "users.list", &BarHandlers.get_user/2
end

defmodule RpcElixir.CodegenTest.LeafBranchCollisionRouter do
  @moduledoc false
  use RpcElixir.Router
  alias RpcElixir.CodegenFixtures.FooHandlers

  procedure "users", &FooHandlers.get_user/2
  procedure "users.list", &FooHandlers.get_user/2
end

# Router with a Handlers segment in the module name to test fix #5
defmodule RpcElixir.CodegenTest.HandlersDropRouter do
  @moduledoc false
  use RpcElixir.Router
  alias RpcElixir.ManifestFixtures.Handlers

  procedure "auth.me", &Handlers.get_user/2
end

# Router with a wrapped-enum error (optional around enum) for fix #4
defmodule RpcElixir.CodegenTest.WrappedEnumErrorRouter do
  @moduledoc false
  use RpcElixir.Router
  alias RpcElixir.CodegenFixtures.WrappedEnumHandlers

  procedure "wrapped.call", &WrappedEnumHandlers.call/2
end

# Router with a union/nullable list field for fix #10
defmodule RpcElixir.CodegenTest.UnionListRouter do
  @moduledoc false
  use RpcElixir.Router
  alias RpcElixir.CodegenFixtures.UnionListHandlers

  procedure "union.list", &UnionListHandlers.call/2
end

# Router with no error on any procedure for fix #3
defmodule RpcElixir.CodegenTest.NoErrorRouter do
  @moduledoc false
  use RpcElixir.Router
  alias RpcElixir.CodegenFixtures.Handlers

  procedure "ping", &Handlers.list_active/2
end

defmodule RpcElixir.CodegenTest.AuthMiddleware do
  @moduledoc false
  @behaviour RpcElixir.Middleware

  @impl true
  def call(res, _opts), do: res

  @impl true
  def rpc_error_codes(_opts), do: [:unauthorized]
end

defmodule RpcElixir.CodegenTest.NoCodesMiddleware do
  @moduledoc false
  @behaviour RpcElixir.Middleware

  @impl true
  def call(res, _opts), do: res
end

defmodule RpcElixir.CodegenTest.MiddlewareErrorRouter do
  @moduledoc false
  use RpcElixir.Router
  alias RpcElixir.CodegenTest.AuthMiddleware
  alias RpcElixir.ManifestFixtures.Handlers

  # list_users has no declared error (→ `never`). get_user already declares
  # `unauthorized` in its @spec, so the middleware code must de-dup, not double.
  procedure "users.list", &Handlers.list_users/2, middleware: [AuthMiddleware]
  procedure "users.get", &Handlers.get_user/2, middleware: [AuthMiddleware]
end

defmodule RpcElixir.CodegenTest.NoCodesMiddlewareRouter do
  @moduledoc false
  use RpcElixir.Router
  alias RpcElixir.CodegenTest.NoCodesMiddleware
  alias RpcElixir.ManifestFixtures.Handlers

  procedure "users.list", &Handlers.list_users/2, middleware: [NoCodesMiddleware]
end

# Router using a custom type that exposes ts_type/0 - exercises branded custom types.
defmodule RpcElixir.CodegenTest.BrandedCustomRouter do
  @moduledoc false
  use RpcElixir.Router
  alias RpcElixir.CodegenFixtures.BrandedCustomHandlers

  procedure "branded.call", &BrandedCustomHandlers.call/2
end

# Routers exercising brand-collision and ts_type/0 validation guards.
defmodule RpcElixir.CodegenTest.DupBrandRouter do
  @moduledoc false
  use RpcElixir.Router
  alias RpcElixir.CodegenFixtures.DupBrandHandlers
  procedure "dup.call", &DupBrandHandlers.call/2
end

defmodule RpcElixir.CodegenTest.ReservedBrandRouter do
  @moduledoc false
  use RpcElixir.Router
  alias RpcElixir.CodegenFixtures.ReservedBrandHandlers
  procedure "reserved.call", &ReservedBrandHandlers.call/2
end

defmodule RpcElixir.CodegenTest.StructClashRouter do
  @moduledoc false
  use RpcElixir.Router
  alias RpcElixir.CodegenFixtures.StructClashHandlers
  procedure "clash.call", &StructClashHandlers.call/2
end

defmodule RpcElixir.CodegenTest.BadIdentifierRouter do
  @moduledoc false
  use RpcElixir.Router
  alias RpcElixir.CodegenFixtures.BadIdentifierHandlers
  procedure "bad.call", &BadIdentifierHandlers.call/2
end

defmodule RpcElixir.CodegenTest.NonStringRouter do
  @moduledoc false
  use RpcElixir.Router
  alias RpcElixir.CodegenFixtures.NonStringHandlers
  procedure "nonstring.call", &NonStringHandlers.call/2
end

defmodule RpcElixir.CodegenTest.NonStringWireRouter do
  @moduledoc false
  use RpcElixir.Router
  alias RpcElixir.CodegenFixtures.NonStringWireHandlers
  procedure "nonstringwire.call", &NonStringWireHandlers.call/2
end

defmodule RpcElixir.CodegenTest.BoolWireRouter do
  @moduledoc false
  use RpcElixir.Router
  alias RpcElixir.CodegenFixtures.BoolWireHandlers
  procedure "boolwire.call", &BoolWireHandlers.call/2
end

defmodule RpcElixir.CodegenTest.UnixMillisAliasRouter do
  @moduledoc false
  use RpcElixir.Router, wire_aliases: [{DateTime, RpcElixir.UnixMillis}]
  alias RpcElixir.ManifestFixtures.Handlers

  procedure "users.create", &Handlers.create_user/2
end

defmodule RpcElixir.CodegenTest.ReservedWordRouter do
  @moduledoc false
  use RpcElixir.Router
  alias RpcElixir.CodegenFixtures.ReservedWordHandlers
  procedure "reservedword.call", &ReservedWordHandlers.call/2
end

defmodule RpcElixir.CodegenTest.TwoDistinctBrandRouter do
  @moduledoc false
  use RpcElixir.Router
  alias RpcElixir.CodegenFixtures.TwoDistinctBrandHandlers
  procedure "two.call", &TwoDistinctBrandHandlers.call/2
end

defmodule RpcElixir.CodegenTest.BrandInListRouter do
  @moduledoc false
  use RpcElixir.Router
  alias RpcElixir.CodegenFixtures.BrandInListHandlers
  procedure "brandlist.call", &BrandInListHandlers.call/2
end

defmodule RpcElixir.CodegenTest.StructuralNameRouter do
  @moduledoc false
  use RpcElixir.Router
  alias RpcElixir.CodegenFixtures.StructuralNameHandlers
  procedure "structural.call", &StructuralNameHandlers.call/2
end

defmodule RpcElixir.CodegenTest.FloatWireRouter do
  @moduledoc false
  use RpcElixir.Router
  alias RpcElixir.CodegenFixtures.FloatWireHandlers
  procedure "floatwire.call", &FloatWireHandlers.call/2
end

defmodule RpcElixir.CodegenTest.EctoUnixMillisAliasRouter do
  @moduledoc false
  use RpcElixir.Router, wire_aliases: [{DateTime, RpcElixir.UnixMillis}]
  alias RpcElixir.CodegenFixtures.EctoTimestampHandlers
  procedure "ecto.call", &EctoTimestampHandlers.call/2
end

defmodule RpcElixir.CodegenTest.EctoNoAliasRouter do
  @moduledoc false
  use RpcElixir.Router
  alias RpcElixir.CodegenFixtures.EctoTimestampHandlers
  procedure "ecto.call", &EctoTimestampHandlers.call/2
end

defmodule RpcElixir.CodegenTest.DateToSkuAliasRouter do
  @moduledoc false
  use RpcElixir.Router, wire_aliases: [{Date, RpcElixir.TypespecFixtures.Sku}]
  alias RpcElixir.CodegenFixtures.AliasedDateHandlers
  procedure "date.call", &AliasedDateHandlers.call/2
end

defmodule RpcElixir.CodegenTest.WrappedDateTimeAliasRouter do
  @moduledoc false
  use RpcElixir.Router, wire_aliases: [{DateTime, RpcElixir.UnixMillis}]
  alias RpcElixir.CodegenFixtures.WrappedDateTimeHandlers
  procedure "wrapped.call", &WrappedDateTimeHandlers.call/2
end

defmodule RpcElixir.CodegenTest.MultiAliasRouter do
  @moduledoc false
  use RpcElixir.Router,
    wire_aliases: [{DateTime, RpcElixir.UnixMillis}, {Date, RpcElixir.TypespecFixtures.Sku}]

  alias RpcElixir.CodegenFixtures.MultiAliasHandlers
  procedure "multi.call", &MultiAliasHandlers.call/2
end

defmodule RpcElixir.CodegenTest.RecursiveTreeRouter do
  @moduledoc false
  use RpcElixir.Router
  alias RpcElixir.CodegenFixtures.RecursiveTreeHandlers
  procedure "tree.get", &RecursiveTreeHandlers.call/2
end

defmodule RpcElixir.CodegenTest.MutuallyRecursiveRouter do
  @moduledoc false
  use RpcElixir.Router
  alias RpcElixir.CodegenFixtures.MutuallyRecursiveHandlers
  procedure "graph.get", &MutuallyRecursiveHandlers.call/2
end

defmodule RpcElixir.CodegenTest.CodeWithDetailsRouter do
  @moduledoc false
  use RpcElixir.Router
  alias RpcElixir.CodegenFixtures.CodeWithDetailsHandlers
  procedure "cwd.call", &CodeWithDetailsHandlers.call/2
end

defmodule RpcElixir.CodegenTest do
  use ExUnit.Case, async: true

  alias RpcElixir.Codegen
  alias RpcElixir.CodegenTest.DocSanitizeRouter
  alias RpcElixir.CodegenTest.Router
  alias RpcElixir.CodegenTest.WeirdRouter

  describe "generate/2" do
    setup do
      source = Codegen.generate(Router)
      {:ok, source: source}
    end

    test "contains AUTO-GENERATED header", %{source: source} do
      assert source =~ "AUTO-GENERATED"
    end

    test "imports createClient from default package", %{source: source} do
      assert source =~
               ~r/import \{ createClient, rpcMethod,[^}]*type Client[^}]*\} from "@elixir-ts-rpc\/client"/
    end

    test "respects custom client_import option" do
      source = Codegen.generate(Router, client_import: "@my-org/rpc-client")
      assert source =~ ~s(from "@my-org/rpc-client")
    end

    test "emits GetUser input interface name (Handlers prefix dropped)", %{source: source} do
      assert source =~ "export interface ManifestFixturesGetUserInput"
    end

    test "emits GetUser output interface name (Handlers prefix dropped)", %{source: source} do
      assert source =~ "export interface ManifestFixturesGetUserOutput"
    end

    test "emits GetUser error type name (Handlers prefix dropped)", %{source: source} do
      assert source =~ "export type ManifestFixturesGetUserError"
    end

    test "emits ListUsers input interface name (Handlers prefix dropped)", %{source: source} do
      assert source =~ "export interface ManifestFixturesListUsersInput"
    end

    test "emits CreateUser input interface name (Handlers prefix dropped)", %{source: source} do
      assert source =~ "export interface ManifestFixturesCreateUserInput"
    end

    test "emits optional properties with ?", %{source: source} do
      assert source =~ "include_deleted?: boolean"
    end

    test "emits enum as string-literal union", %{source: source} do
      assert source =~ ~s("not_found" | "unauthorized")
    end

    test "does not emit the dead Procedures/ProcedureName/_procedures exports", %{source: source} do
      refute source =~ "export type Procedures"
      refute source =~ "export type ProcedureName"
      refute source =~ "export const _procedures"
    end

    test "emits RpcClient type as nested tree", %{source: source} do
      assert source =~ "export type RpcClient = {"
      # branch for the "users" namespace
      assert source =~ "users: {"
      # leaf methods inside the branch - typed RpcMethod (callable + isError guard)
      assert source =~
               "get: RpcMethod<ManifestFixturesGetUserInput, ManifestFixturesGetUserOutput, ManifestFixturesGetUserError>;"

      assert source =~
               "list: RpcMethod<ManifestFixturesListUsersInput, ManifestFixturesListUsersOutput, ManifestFixturesListUsersError>;"

      # no flat dotted keys as method names in the client type or runtime object
      refute source =~ ~s|"users.get": RpcMethod|
    end

    test "emits JSDoc from procedure doc", %{source: source} do
      assert source =~ "Get a user by id."
    end

    test "emits createRpcClient function", %{source: source} do
      assert source =~ "export function createRpcClient"
    end

    test "emits createClient call in createRpcClient", %{source: source} do
      assert source =~ "const client: Client = createClient(opts)"
    end

    test "emits nested object in createRpcClient", %{source: source} do
      # branch key
      assert source =~ "users: {"
      # leaf binds a typed rpcMethod to the full dotted procedure name and its
      # declared error codes (used by `.isError` to narrow soundly at runtime)
      assert source =~
               "get: rpcMethod<ManifestFixturesGetUserInput, ManifestFixturesGetUserOutput, ManifestFixturesGetUserError>(client, \"users.get\", [\"not_found\", \"unauthorized\"])"
    end
  end

  describe "name mapping behavior" do
    test "uses short names (strips module prefix and Handlers segment) when no collisions" do
      source = Codegen.generate(Router)
      assert source =~ "ManifestFixturesGetUserInput"
      refute source =~ "ManifestFixturesHandlersGetUserInput"
      refute source =~ ~r/export (?:type|interface) RpcElixirCodegen/
    end

    test "uses fully-qualified names when two handlers share a function name" do
      source = Codegen.generate(RpcElixir.CodegenTest.CollisionRouter)
      assert source =~ "FooHandlersGetUserInput"
      assert source =~ "BarHandlersGetUserInput"
    end

    test "all generated type names are unique" do
      source = Codegen.generate(Router)

      type_names =
        Regex.scan(~r/export (?:type|interface) (\w+)/, source, capture: :all_but_first)

      flat_names = List.flatten(type_names)
      assert flat_names == Enum.uniq(flat_names)
    end
  end

  describe "prop key quoting" do
    test "bare name for valid identifiers" do
      source = Codegen.generate(WeirdRouter)
      assert source =~ "normal?"
    end

    test "JSON-quoted name for non-identifier keys" do
      source = Codegen.generate(WeirdRouter)
      assert source =~ ~s("weird-key"?)
      assert source =~ ~s("@type"?)
      assert source =~ ~s("0start"?)
    end
  end

  describe "doc sanitization" do
    test "sanitizes */ in procedure description" do
      source = Codegen.generate(DocSanitizeRouter)
      assert source =~ "Proc with * / in its description"
      refute source =~ "Proc with */"
    end
  end

  describe "top-level def emission" do
    test "emits interface for object IR via generate/2" do
      source = Codegen.generate(Router)
      assert source =~ "export interface ManifestFixturesGetUserInput {"
      assert source =~ "id: string"
      assert source =~ "include_deleted?: boolean"
    end

    test "emits enum error as DomainError<codes> union" do
      source = Codegen.generate(Router)

      assert source =~
               ~s(export type ManifestFixturesGetUserError = DomainError<"not_found" | "unauthorized">)
    end

    test "emits never for nil error (fix #6)" do
      source = Codegen.generate(Router)
      assert source =~ "export type ManifestFixturesListUsersError = never"
    end

    test "object error with code + details widens details to `| undefined`" do
      source = Codegen.generate(RpcElixir.CodegenTest.CodeWithDetailsRouter)

      assert source =~
               ~r/= DomainError<"rate_limited" \| "quota_exceeded", \{ retry_after: number \} \| undefined>;/
    end
  end

  describe "middleware-contributed error codes" do
    test "folds declared middleware codes into a no-error procedure's type and isError codes" do
      source = Codegen.generate(RpcElixir.CodegenTest.MiddlewareErrorRouter)

      assert source =~
               "list: RpcMethod<ManifestFixturesListUsersInput, ManifestFixturesListUsersOutput, ManifestFixturesListUsersError | MiddlewareError<\"unauthorized\">>;"

      assert source =~
               "list: rpcMethod<ManifestFixturesListUsersInput, ManifestFixturesListUsersOutput, ManifestFixturesListUsersError | MiddlewareError<\"unauthorized\">>(client, \"users.list\", [\"unauthorized\"])"
    end

    test "de-dups a middleware code already declared in the handler @spec" do
      source = Codegen.generate(RpcElixir.CodegenTest.MiddlewareErrorRouter)

      # get_user's @spec already has `unauthorized`. The runtime codes must not repeat it.
      assert source =~ ~s("users.get", ["not_found", "unauthorized"])
      refute source =~ ~s(["not_found", "unauthorized", "unauthorized"])
    end

    test "middleware without rpc_error_codes/1 contributes nothing (backward compatible)" do
      source = Codegen.generate(RpcElixir.CodegenTest.NoCodesMiddlewareRouter)

      assert source =~
               "list: RpcMethod<ManifestFixturesListUsersInput, ManifestFixturesListUsersOutput, ManifestFixturesListUsersError>;"

      assert source =~ ~s("users.list", [])
      refute source =~ ~s(ManifestFixturesListUsersError | MiddlewareError)
    end
  end

  describe "T[] list syntax" do
    test "emits T[] instead of Array<T> for simple inner type" do
      source = Codegen.generate(Router)
      refute source =~ "Array<"
    end

    test "emits (T | U)[] for union/nullable inner type in list (fix #10)" do
      source = Codegen.generate(RpcElixir.CodegenTest.UnionListRouter)
      # the nullable list field should produce (string | null)[]
      assert source =~ "(string | null)[]"
    end
  end

  describe "error-type imports" do
    test "imports DomainError when a procedure declares a coded error union" do
      source = Codegen.generate(Router)
      assert source =~ ~r/import \{[^}]*type DomainError[^}]*\} from "@elixir-ts-rpc\/client";/
    end

    test "imports neither error-shape type (nor RpcError) when no procedure has a typed error" do
      source = Codegen.generate(RpcElixir.CodegenTest.NoErrorRouter)
      refute source =~ "DomainError"
      refute source =~ "MiddlewareError"
      refute source =~ "RpcError"
    end
  end

  describe "Handlers prefix dropped from short names (fix #5)" do
    test "Handlers segment is stripped from generated names" do
      source = Codegen.generate(RpcElixir.CodegenTest.HandlersDropRouter)
      assert source =~ "ManifestFixturesGetUserInput"
      refute source =~ "ManifestFixturesHandlersGetUserInput"
    end
  end

  describe "wrapped-enum error detection (fix #4)" do
    test "optional-wrapped enum error emits DomainError<...>" do
      source = Codegen.generate(RpcElixir.CodegenTest.WrappedEnumErrorRouter)
      assert source =~ ~r/export type \w+Error = DomainError<"[^"]+"/
    end
  end

  describe "branded custom types (ts_type/0)" do
    setup do
      source = Codegen.generate(RpcElixir.CodegenTest.BrandedCustomRouter)
      {:ok, source: source}
    end

    test "auto-emits branded TS alias for the custom type", %{source: source} do
      assert source =~
               ~s(export type Int64String = string & { readonly __brand: "Int64String" };)
    end

    test "uses the brand name in interface fields", %{source: source} do
      assert source =~ "id: Int64String"
    end

    test "skips client-side coercion for branded customs", %{source: source} do
      refute source =~ "_coercionSchema"

      assert source =~
               ~s/call: rpcMethod<CodegenFixturesBrandedCustomHandlersCallInput, CodegenFixturesBrandedCustomHandlersCallOutput, CodegenFixturesBrandedCustomHandlersCallError>(client, "branded.call", []),/
    end
  end

  describe "brand-collision and ts_type/0 validation" do
    test "raises when two custom types claim the same brand name" do
      assert_raise RuntimeError, ~r/DupBrand.*claimed by multiple custom types/, fn ->
        Codegen.generate(RpcElixir.CodegenTest.DupBrandRouter)
      end
    end

    test "raises when a custom brand collides with a built-in brand" do
      assert_raise RuntimeError, ~r/DecimalString.*reserved built-in brand/, fn ->
        Codegen.generate(RpcElixir.CodegenTest.ReservedBrandRouter)
      end
    end

    test "raises when a custom brand collides with a generated struct interface" do
      assert_raise RuntimeError, ~r/Product.*collides with a generated struct interface/, fn ->
        Codegen.generate(RpcElixir.CodegenTest.StructClashRouter)
      end
    end

    test "raises when ts_type/0 returns a non-identifier string" do
      assert_raise RuntimeError, ~r/not a valid TypeScript identifier/, fn ->
        Codegen.generate(RpcElixir.CodegenTest.BadIdentifierRouter)
      end
    end

    test "raises when ts_type/0 returns a non-string" do
      assert_raise RuntimeError, ~r/must return a String/, fn ->
        Codegen.generate(RpcElixir.CodegenTest.NonStringRouter)
      end
    end

    test "raises when a branded custom has a non-string, non-number wire_spec" do
      assert_raise RuntimeError, ~r/require a string or number wire/i, fn ->
        Codegen.generate(RpcElixir.CodegenTest.BoolWireRouter)
      end
    end

    test "emits a number brand when a branded custom has an integer wire_spec" do
      source = Codegen.generate(RpcElixir.CodegenTest.NonStringWireRouter)

      assert source =~
               ~s(export type IntWire = number & { readonly __brand: "IntWire" };)
    end

    test "emits a number brand when a branded custom has a float wire_spec" do
      source = Codegen.generate(RpcElixir.CodegenTest.FloatWireRouter)

      assert source =~
               ~s(export type Latitude = number & { readonly __brand: "Latitude" };)

      assert source =~ "lat: Latitude"
    end

    test "emits a string brand when a branded custom has a string wire_spec" do
      source = Codegen.generate(RpcElixir.CodegenTest.TwoDistinctBrandRouter)

      assert source =~
               ~s(export type Int64String = string & { readonly __brand: "Int64String" };)
    end

    test "raises when a custom brand collides with a reserved TypeScript type name" do
      assert_raise RuntimeError, ~r/Date.*reserved TypeScript or generated type name/, fn ->
        Codegen.generate(RpcElixir.CodegenTest.ReservedWordRouter)
      end
    end

    test "raises when a custom brand collides with a generated structural name" do
      assert_raise RuntimeError, ~r/RpcClient.*reserved TypeScript or generated type name/, fn ->
        Codegen.generate(RpcElixir.CodegenTest.StructuralNameRouter)
      end
    end

    test "two distinct branded customs in one router do not raise" do
      source = Codegen.generate(RpcElixir.CodegenTest.TwoDistinctBrandRouter)
      assert source =~ ~s(export type Int64String = string &)
      assert source =~ ~s(export type Sku = string &)
    end

    test "validates and brands a custom nested inside a list" do
      source = Codegen.generate(RpcElixir.CodegenTest.BrandInListRouter)
      assert source =~ "Int64String[]"
    end
  end

  describe "collision handling" do
    test "FooHandlers and BarHandlers with same function name get fully-qualified names" do
      source = Codegen.generate(RpcElixir.CodegenTest.CombinedRouter)

      assert source =~ "FooHandlersGetUserInput"
      assert source =~ "BarHandlersGetUserInput"
      refute source =~ ~r/\bGetUserInput\b/
    end
  end

  describe "nested tree shape" do
    test "(a) single-segment procedure becomes a top-level method" do
      source = Codegen.generate(RpcElixir.CodegenTest.PingRouter)
      # single-segment procedure is a top-level method (leaf), not a branch
      assert source =~ "ping: rpcMethod<"
      # no dotted-style method call syntax
      refute source =~ ~s|"ping"(input|
      refute source =~ ~s|"ping": (input|
    end

    test "(b) 2-level dotted name emits a branch and a leaf" do
      source = Codegen.generate(RpcElixir.CodegenTest.FooRouter)
      assert source =~ "foo: {"
      assert source =~ "get: rpcMethod<"
      # no flat dotted-method style in the client type or factory
      refute source =~ ~s|"foo.get"(input|
      refute source =~ ~s|"foo.get": (input|
    end

    test "(c) 3-level dotted name emits two branches and a leaf" do
      source = Codegen.generate(RpcElixir.CodegenTest.DeepRouter)
      assert source =~ "users: {"
      assert source =~ "profile: {"
      assert source =~ "update: rpcMethod<"
    end

    test "(d) sibling leaves under the same branch are both emitted" do
      source = Codegen.generate(RpcElixir.CodegenTest.SiblingRouter)
      assert source =~ "users: {"
      assert source =~ "get: rpcMethod<"
      assert source =~ "list: rpcMethod<"
    end

    test "(e) leaf-vs-branch name collision raises a clear error at codegen time" do
      assert_raise RuntimeError, ~r/name collision/, fn ->
        Codegen.generate(RpcElixir.CodegenTest.LeafBranchCollisionRouter)
      end
    end

    test "createRpcClient nested object has matching structure" do
      source = Codegen.generate(RpcElixir.CodegenTest.SiblingRouter)
      assert source =~ "users: {"
      # leaf still calls with the original dotted name
      assert source =~ ~s("users.get")
      assert source =~ ~s("users.list")
    end
  end

  describe "unhandled IR kind (fix #9)" do
    alias RpcElixir.Codegen.Render

    test "ir_to_ts_type raises instead of degrading an unknown kind to \"unknown\"" do
      assert_raise ArgumentError, ~r/unhandled IR kind "bogus_kind".*ir_to_ts_type/, fn ->
        Render.ir_to_ts_type(%{kind: "bogus_kind"}, %{}, [])
      end
    end

    test "ir_to_ts_type raises for a non-map IR with no kind" do
      assert_raise ArgumentError, ~r/unhandled IR kind/, fn ->
        Render.ir_to_ts_type(:not_an_ir, %{}, [])
      end
    end
  end

  describe "recursive struct interfaces" do
    test "self-referential struct emits an interface that references itself by name" do
      source = Codegen.generate(RpcElixir.CodegenTest.RecursiveTreeRouter)
      # The TreeNode interface must exist and reference itself in the children field.
      assert source =~ ~r/export interface TreeNode \{/
      assert source =~ ~r/children: TreeNode\[\]/
      # The label field should be a plain string.
      assert source =~ ~r/label: string/
      # No infinite loop occurred - generate/2 returned.
    end

    test "mutually-recursive structs emit two interfaces that cross-reference each other" do
      source = Codegen.generate(RpcElixir.CodegenTest.MutuallyRecursiveRouter)
      # Both interfaces must be emitted.
      assert source =~ ~r/export interface GraphNodeA \{/
      assert source =~ ~r/export interface GraphNodeB \{/
      # A references B and B references A (by interface name).
      assert source =~ ~r/next: GraphNodeB \| null/
      assert source =~ ~r/prev: GraphNodeA \| null/
    end

    test "recursive generate/2 does not hang - returns in finite time" do
      # If the walker were still infinite-looping, this would time-out rather than
      # reaching the assertion. The test itself is the liveness proof.
      assert is_binary(Codegen.generate(RpcElixir.CodegenTest.RecursiveTreeRouter))
      assert is_binary(Codegen.generate(RpcElixir.CodegenTest.MutuallyRecursiveRouter))
    end
  end
end

defmodule RpcElixir.CodegenDatetimeTest do
  use ExUnit.Case, async: true

  alias RpcElixir.Codegen
  alias RpcElixir.CodegenTest.Router

  test "DateTime.t() defaults to the DateTimeString ISO brand" do
    source = Codegen.generate(Router)

    assert source =~ "export type DateTimeString = string & "
    assert source =~ ~r/created_at\??: DateTimeString/
  end

  test "no datetime coercion machinery is emitted" do
    refute Codegen.generate(Router) =~ "_coercionSchema"
  end
end

defmodule RpcElixir.CodegenWireAliasTest do
  use ExUnit.Case, async: true

  alias RpcElixir.Codegen
  alias RpcElixir.CodegenTest.{Router, UnixMillisAliasRouter}

  test "wire_aliases maps DateTime to the UnixMillis EpochMillis number brand" do
    source = Codegen.generate(UnixMillisAliasRouter)

    assert source =~
             ~s(export type EpochMillis = number & { readonly __brand: "EpochMillis" };)

    assert source =~ ~r/created_at\??: EpochMillis/
    refute source =~ "DateTimeString"
  end

  test "without the alias the same DateTime field stays the DateTimeString ISO brand" do
    source = Codegen.generate(Router)

    assert source =~ "export type DateTimeString = string & "
    refute source =~ "EpochMillis"
  end

  test "alias applies to an Ecto :utc_datetime field (declares EpochMillis, drops DateTimeString)" do
    source = Codegen.generate(RpcElixir.CodegenTest.EctoUnixMillisAliasRouter)

    assert source =~
             ~s(export type EpochMillis = number & { readonly __brand: "EpochMillis" };)

    # A branded custom type used as a struct-interface field must render as its brand,
    # not its bare wire primitive (regression: render_with_struct_map stripped the brand).
    assert source =~ ~r/created_at\??: EpochMillis/
    refute source =~ "DateTimeString"
  end

  test "without the alias the same Ecto :utc_datetime field stays the DateTimeString ISO brand" do
    source = Codegen.generate(RpcElixir.CodegenTest.EctoNoAliasRouter)

    assert source =~ "export type DateTimeString = string & "
    assert source =~ ~r/created_at\??: DateTimeString/
    refute source =~ "EpochMillis"
  end

  test "alias resolves through list, nullable, and optional wrappers" do
    source = Codegen.generate(RpcElixir.CodegenTest.WrappedDateTimeAliasRouter)

    refute source =~ "DateTimeString"
    assert source =~ "many: EpochMillis[]"
    assert source =~ ~r/maybe: EpochMillis \| null/
    assert source =~ "lazy?: EpochMillis"
  end

  test "multiple aliases coexist and apply independently" do
    source = Codegen.generate(RpcElixir.CodegenTest.MultiAliasRouter)

    assert source =~ ~s(export type EpochMillis = number & { readonly __brand: "EpochMillis" };)
    assert source =~ ~s(export type Sku = string & { readonly __brand: "Sku" };)
    assert source =~ "at: EpochMillis"
    assert source =~ "day: Sku"
    refute source =~ "DateTimeString"
  end

  test "alias to a string-wire custom emits that custom's string brand" do
    source = Codegen.generate(RpcElixir.CodegenTest.DateToSkuAliasRouter)

    assert source =~ ~s(export type Sku = string & { readonly __brand: "Sku" };)
    assert source =~ ~r/when: Sku/
  end
end
