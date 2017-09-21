defmodule EctoReplaySandbox.Integration.Migration do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :name, :text
      timestamps()
    end

    create table(:posts) do
      add :title, :string, size: 100
      add :counter, :integer
      add :text, :binary
      add :public, :boolean
      add :cost, :decimal, precision: 2, scale: 1
      add :visits, :integer
      add :intensity, :float
      add :author_id, :integer
      add :posted, :date
      timestamps null: true
    end

    create table(:comments) do
      add :text, :string, size: 100
      add :post_id, references(:posts)
      add :author_id, references(:users)
    end
 
  end
end
