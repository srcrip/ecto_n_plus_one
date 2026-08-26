import Config

config :ecto_n_plus_one_demo, EctoNPlusOneDemo.Repo,
  database: Path.expand("../ecto_n_plus_one_demo_dev.db", __DIR__),
  pool_size: 5,
  stacktrace: true,
  log_stacktrace_mfa: {Ecto.Adapters.SQL, :first_non_ecto_stacktrace, [5]},
  show_sensitive_data_on_connection_error: true

config :ecto_n_plus_one_demo, EctoNPlusOneDemoWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 7070],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "RYLpKTrhP1Kxa7ADe0equKLdARwJ9OQXKf0c6WaHcJk16lEkebmi16W5iHFIJw9l",
  watchers: []

config :logger, :default_formatter, format: "[$level] $message\n"
