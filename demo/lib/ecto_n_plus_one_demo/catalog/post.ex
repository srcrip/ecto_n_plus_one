defmodule EctoNPlusOneDemo.Catalog.Post do
  use Ecto.Schema

  import Ecto.Changeset

  alias EctoNPlusOneDemo.Catalog.Author

  schema "posts" do
    field :title, :string
    belongs_to :author, Author

    timestamps(type: :utc_datetime)
  end

  def changeset(post, attrs) do
    post
    |> cast(attrs, [:title])
    |> validate_required([:title])
  end
end
