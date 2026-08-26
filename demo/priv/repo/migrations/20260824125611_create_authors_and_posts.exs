defmodule EctoNPlusOneDemo.Repo.Migrations.CreateAuthorsAndPosts do
  use Ecto.Migration

  def change do
    create table(:authors) do
      add :name, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create table(:posts) do
      add :title, :string, null: false
      add :author_id, references(:authors, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:posts, [:author_id])
  end
end
