defmodule CockroachDBSandbox.Integration.Migration do
  use Ecto.Migration

  def change do
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
 
  end
end
