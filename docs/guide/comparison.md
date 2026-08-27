# Comparison

Every alternative here asks you to maintain a description of your API. It might
be a GraphQL schema, an OpenAPI document, a `.proto`, or a hand-written
`types.ts`. It lives apart from your Elixir code.

This library bets you already wrote that description. It is the function itself.
A procedure is an ordinary Elixir function, and the contract is that function's
own signature. So there is no schema at all, not merely no *second* schema.

`RpcElixir.Types.FromSpec` recovers that signature today. It reads your `@spec`
from compiled BEAM debug info. Elixir's set-theoretic type signatures land next.
`FromInferred` will then read the signature from the compiler directly. Either
way, both sides come from one read of one source of truth. The dispatcher
validates against it in both directions.

It also means registration stays small. A router lists handler modules, not one
entry per operation: `expose MyApp.Users` publishes every spec'd function in the
module, and `procedure` is there when you want to name them one at a time.

It also means the generated client can point back at its origin. Each method
carries a link to the handler line it came from, so a TypeScript call is one
click from the Elixir that answers it.

## At a glance

| Approach                  | Contract lives in  | Other-language clients | Realtime      |
| ------------------------- | ------------------ | ---------------------- | ------------- |
| elixir-ts-rpc             | your function      | none                   | planned       |
| Hand-written JSON + types | nothing formal     | you write them         | roll your own |
| Absinthe (GraphQL)        | GraphQL schema     | mature ecosystem       | subscriptions |
| OpenApiSpex + codegen     | OpenAPI document   | mature ecosystem       | out of scope  |
| Phoenix LiveView          | no client boundary | not applicable         | built in      |
| gRPC / protobuf           | `.proto`           | mature ecosystem       | streaming     |

Four of those five are more mature than this library. Three of them offer what
it cannot: a contract another language can read.

## The alternatives

**Hand-written JSON endpoints.** Phoenix controllers with JSON views, plus
TypeScript interfaces you maintain by hand. There are no dependencies and no
codegen. You keep full control of URLs, status codes, and caching. But the types
are a claim, not a check. You also write request validation per endpoint.

**Absinthe / GraphQL.** This is the most mature typed-API story in Elixir. It is
probably still the right answer for a public or multi-client API. Any language
can consume the schema. Clients pick the fields they need. Subscriptions ride
Phoenix Channels. The cost is a second description of your domain to maintain.

**OpenApiSpex and `openapi-typescript`.** OpenApiSpex validates requests against
the schemas it publishes. The document is therefore load-bearing at runtime, and
it is language-neutral. You keep Swagger UI, `GET`, and cache headers. The trade
is a second definition of every shape. It lives in an Elixir DSL that mirrors
your structs.

**Phoenix LiveView.** Sometimes there is no client to type. LiveView keeps
state on the server and deletes the serialization boundary. It is usually less
total system than anything else here. The boundary returns when the other side
owns state. That side may be an interactive React surface, offline behaviour, a
native app, or a third party.

**gRPC / protobuf.** A strong fit if your team already thinks in IDLs. There is
codegen for essentially every language. Streaming is part of the protocol. The
framing is binary. Field numbers let you evolve a schema without breaking old
clients. But browsers cannot speak gRPC directly. The `.proto` is another schema
to align by hand.

**tRPC** shares TypeScript types between a Node server and a Node client. So it
cannot serve an Elixir backend. It is the inspiration here, not an alternative.

## Choose it when

- Your backend is Elixir and your frontend is TypeScript you deploy with it.
- You would rather the function be the contract than maintain a second one.
- You want validated inputs and outputs, and typed failure paths, for free.
- Request/response is enough.

If so, read [How it works](/guide/how-it-works). If not, pick a mature option.
