defmodule EctoNPlusOneDemoWeb.AuthorsLive do
  @moduledoc """
  Renders the author list either through the intentionally bad N+1 query path or through the preloaded equivalent,
  depending on the route's live action.

  `EctoNPlusOneDemoWeb.AuthorsLiveTest` uses these to exercise `EctoNPlusOne.Test.assert_no_n_plus_one/2`.
  """

  use Phoenix.LiveView

  alias EctoNPlusOneDemo.Catalog

  @impl true
  def mount(_params, _session, socket) do
    rows =
      case socket.assigns.live_action do
        :preloaded -> Catalog.list_authors_with_posts_preloaded()
        :n_plus_one -> Catalog.list_authors_with_posts_n_plus_one()
      end

    {:ok, assign(socket, :rows, rows)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <h1>Authors</h1>
    <ul>
      <li :for={row <- @rows}>
        {row.author.name}: {Enum.map_join(row.posts, ", ", & &1.title)}
      </li>
    </ul>
    """
  end
end
