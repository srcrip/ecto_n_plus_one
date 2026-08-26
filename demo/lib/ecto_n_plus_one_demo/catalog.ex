defmodule EctoNPlusOneDemo.Catalog do
  @moduledoc """
  Deliberately contains both an N+1 implementation and its preloaded equivalent.
  """

  import Ecto.Query

  alias EctoNPlusOneDemo.Catalog.{Author, Post}
  alias EctoNPlusOneDemo.Repo

  @doc "Runs one post query per author. This is intentionally bad."
  def list_authors_with_posts_n_plus_one do
    Author
    |> order_by([author], author.name)
    |> Repo.all()
    |> Enum.map(&load_posts/1)
  end

  @doc "Loads the same data with a bounded pair of queries."
  def list_authors_with_posts_preloaded do
    Author
    |> order_by([author], author.name)
    |> preload(:posts)
    |> Repo.all()
    |> Enum.map(&%{author: &1, posts: &1.posts})
  end

  defp load_posts(author) do
    posts =
      Post
      |> where([post], post.author_id == ^author.id)
      |> order_by([post], post.title)
      |> Repo.all()

    %{author: author, posts: posts}
  end
end
