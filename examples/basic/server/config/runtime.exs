import Config

secret_key_base =
  System.get_env("SECRET_KEY_BASE") || String.duplicate("a", 64)

config :basic_server, secret_key_base: secret_key_base
