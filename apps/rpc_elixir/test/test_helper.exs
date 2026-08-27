# `RpcElixir.Types.FromInferred` reads Elixir's set-theoretic signatures, which
# only exist from 1.19 on. Its tests are excluded on older versions rather than
# left to fail.
inference_exclude =
  if Version.match?(System.version(), ">= 1.19.0"), do: [], else: [:requires_inference]

ExUnit.start(exclude: [:bench, :integration] ++ inference_exclude)
