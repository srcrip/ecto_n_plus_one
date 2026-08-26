alias EctoNPlusOneDemo.Catalog.{Author, Post}
alias EctoNPlusOneDemo.Repo

Repo.delete_all(Post)
Repo.delete_all(Author)

["Ada Lovelace", "Edsger Dijkstra", "Grace Hopper", "Barbara Liskov", "Donald Knuth"]
|> Enum.with_index(1)
|> Enum.each(fn {name, index} ->
  author = Repo.insert!(Author.changeset(%Author{}, %{name: name}))

  ["A first post", "A second post"]
  |> Enum.with_index(1)
  |> Enum.each(fn {label, post_index} ->
    author
    |> Ecto.build_assoc(:posts)
    |> Post.changeset(%{title: "#{label} by author #{index} (#{post_index})"})
    |> Repo.insert!()
  end)
end)
