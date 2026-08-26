defmodule EctoNPlusOneDemo.Fixtures do
  alias EctoNPlusOneDemo.Catalog.{Author, Post}
  alias EctoNPlusOneDemo.Repo

  def create_authors_with_posts(count) do
    Enum.map(1..count, fn index ->
      author = Repo.insert!(Author.changeset(%Author{}, %{name: "Author #{index}"}))

      post =
        author
        |> Ecto.build_assoc(:posts)
        |> Post.changeset(%{title: "Post #{index}"})
        |> Repo.insert!()

      %{author: author, posts: [post]}
    end)
  end
end
