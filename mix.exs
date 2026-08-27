defmodule EctoNPlusOne.MixProject do
  use Mix.Project

  def project do
    [
      app: :ecto_n_plus_one,
      version: "0.1.0",
      elixir: "~> 1.14",
      name: "EctoNPlusOne",
      description: "N+1 query detection for Ecto",
      source_url: "https://github.com/srcrip/ecto_n_plus_one",
      package: package(),
      docs: docs(),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ecto_sql, "~> 3.11"},
      {:nimble_options, "~> 1.1"},
      {:telemetry, "~> 1.2"},
      {:ex_check, "~> 0.16.0", only: :dev, runtime: false},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "Documentation" => "https://hexdocs.pm/ecto_n_plus_one",
        "GitHub" => "https://github.com/srcrip/ecto_n_plus_one"
      },
      files: ~w(lib .formatter.exs mix.exs README.md CHANGELOG.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md", "LICENSE"]
    ]
  end
end
