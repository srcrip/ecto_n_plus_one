import Config

config :ecto_n_plus_one_demo, EctoNPlusOneDemo.Repo,
  database: Path.expand("../ecto_n_plus_one_demo_test.db", __DIR__),
  pool_size: 1,
  pool: Ecto.Adapters.SQL.Sandbox,
  stacktrace: true,
  log_stacktrace_mfa: {Ecto.Adapters.SQL, :first_non_ecto_stacktrace, [5]}

config :ecto_n_plus_one_demo, EctoNPlusOneDemoWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "efPkSXtVryvbO3bT+NQMGO/khVJXTXbSGmxF8QObXrlNTH098VRTYQcEfWJ51nAh",
  server: false

config :logger, level: :warning
