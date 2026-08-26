defmodule EctoNPlusOneDemoWeb.PageController do
  use EctoNPlusOneDemoWeb, :controller

  alias EctoNPlusOneDemo.Scenario

  def home(conn, _params) do
    %{rows: rows, detection: detection} = Scenario.run()
    render(conn, :home, rows: rows, detection: detection)
  end
end
