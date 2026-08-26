defmodule EctoNPlusOneDemo.DataCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  setup tags do
    EctoNPlusOneDemo.DataCase.setup_sandbox(tags)
    :ok
  end

  def setup_sandbox(tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(EctoNPlusOneDemo.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
  end
end
