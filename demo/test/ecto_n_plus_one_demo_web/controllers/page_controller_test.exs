defmodule EctoNPlusOneDemoWeb.PageControllerTest do
  use EctoNPlusOneDemoWeb.ConnCase

  alias EctoNPlusOneDemo.Fixtures

  test "GET /", %{conn: conn} do
    Fixtures.create_authors_with_posts(5)

    conn = get(conn, ~p"/")
    html = html_response(conn, 200)

    assert html =~ "N+1 pattern detected"
    assert html =~ "5 executions"
    assert html =~ "5 parameter variants"
    assert html =~ "Author 1"
  end
end
