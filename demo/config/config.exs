import Config

config :ecto_n_plus_one_demo,
  ecto_repos: [EctoNPlusOneDemo.Repo]

config :ecto_n_plus_one_demo, EctoNPlusOneDemoWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [formats: [html: EctoNPlusOneDemoWeb.ErrorHTML], layout: false]

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

import_config "#{config_env()}.exs"
