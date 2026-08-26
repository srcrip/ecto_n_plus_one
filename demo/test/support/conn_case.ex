defmodule EctoNPlusOneDemoWeb.ConnCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint EctoNPlusOneDemoWeb.Endpoint

      use EctoNPlusOneDemoWeb, :verified_routes

      import Phoenix.ConnTest
    end
  end

  setup tags do
    EctoNPlusOneDemo.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
