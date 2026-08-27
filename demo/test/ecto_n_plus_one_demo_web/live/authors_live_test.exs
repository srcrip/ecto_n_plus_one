defmodule EctoNPlusOneDemoWeb.AuthorsLiveTest do
  use EctoNPlusOneDemoWeb.ConnCase

  import Phoenix.LiveViewTest

  use EctoNPlusOne.Test,
    repos: EctoNPlusOneDemo.Repo,
    application_modules: [EctoNPlusOneDemo, EctoNPlusOneDemoWeb]

  alias EctoNPlusOne.Detection
  alias EctoNPlusOneDemo.Fixtures

  test "the preloaded page passes and returns the block's result", %{conn: conn} do
    # Fixture n+1s before the assertion block must not be counted
    Fixtures.create_authors_with_posts(5)

    {:ok, _view, html} = assert_no_n_plus_one(fn -> live(conn, ~p"/authors/preloaded") end)

    assert html =~ "Author 1"
    assert html =~ "Post 5"
  end

  @tag :capture_log
  test "the N+1 page fails with the offending query and callsite", %{conn: conn} do
    Fixtures.create_authors_with_posts(5)

    error =
      assert_raise EctoNPlusOne.Test.NPlusOneDetectedError, fn ->
        assert_no_n_plus_one(fn -> live(conn, ~p"/authors/n-plus-one") end)
      end

    assert [%Detection{source: "posts", operation: :select} = detection] = error.detections

    # `live/2` mounts twice (disconnected and connected), so the 5 per-author queries run 10 times,
    # but with 5 distinct parameter sets either way.
    assert detection.count == 10
    assert detection.parameter_variants == 5
    assert error.message =~ "lib/ecto_n_plus_one_demo/catalog.ex"
  end
end
