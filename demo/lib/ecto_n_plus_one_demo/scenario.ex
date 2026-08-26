defmodule EctoNPlusOneDemo.Scenario do
  @moduledoc """
  Runs the intentionally inefficient query path.

  EctoNPlusOne observes it automatically through the Repo's query Telemetry
  event; this module does not call or wrap the detector.
  """

  alias EctoNPlusOneDemo.{Catalog, DetectionHandler}

  def run do
    rows = Catalog.list_authors_with_posts_n_plus_one()

    %{rows: rows, detection: DetectionHandler.take()}
  end
end
