defmodule EctoNPlusOneDemo.Catalog.Author do
  use Ecto.Schema

  import Ecto.Changeset

  alias EctoNPlusOneDemo.Catalog.Post

  schema "authors" do
    field :name, :string
    has_many :posts, Post

    timestamps(type: :utc_datetime)
  end

  def changeset(author, attrs) do
    author
    |> cast(attrs, [:name])
    |> validate_required([:name])
  end
end
