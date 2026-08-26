defmodule EctoNPlusOneDemo.Repo do
  use Ecto.Repo,
    otp_app: :ecto_n_plus_one_demo,
    adapter: Ecto.Adapters.SQLite3
end
