defmodule EctoNPlusOneDemo.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    :ok =
      EctoNPlusOne.attach(EctoNPlusOneDemo.Repo,
        application_modules: [EctoNPlusOneDemo, EctoNPlusOneDemoWeb],
        on_detect: &EctoNPlusOneDemo.DetectionHandler.handle/1
      )

    children = [
      EctoNPlusOneDemo.Repo,
      EctoNPlusOneDemoWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: EctoNPlusOneDemo.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    EctoNPlusOneDemoWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
