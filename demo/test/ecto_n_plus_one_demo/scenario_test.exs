defmodule EctoNPlusOneDemo.ScenarioTest do
  use EctoNPlusOneDemo.DataCase

  alias EctoNPlusOne.Detection
  alias EctoNPlusOneDemo.{Catalog, DetectionHandler, Fixtures, Scenario}

  test "the deliberate per-author query loop calls the user's handler" do
    Fixtures.create_authors_with_posts(5)

    %{rows: rows, detection: detection} = Scenario.run()

    assert length(rows) == 5
    assert %Detection{} = detection
    assert detection.source == "posts"
    assert detection.count == 5
    assert detection.parameter_variants == 5
    assert match?({Catalog, :load_posts, 1, _location}, detection.callsite)
  end

  test "application code does not manually invoke the detector" do
    Fixtures.create_authors_with_posts(5)

    rows = Catalog.list_authors_with_posts_n_plus_one()

    assert length(rows) == 5
    assert %Detection{count: 5} = DetectionHandler.take()
  end

  test "preloading the posts removes the N+1 pattern" do
    Fixtures.create_authors_with_posts(5)

    rows = Catalog.list_authors_with_posts_preloaded()

    assert length(rows) == 5
    assert DetectionHandler.take() == nil
  end
end
