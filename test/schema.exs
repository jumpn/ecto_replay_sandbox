defmodule EctoReplaySandbox.Integration.Schema do
  defmacro __using__(_) do
    quote do
      use Ecto.Schema

      type =
        Application.get_env(:ecto, :primary_key_type) ||
        raise ":primary_key_type not set in :ecto application"
      @primary_key {:id, type, autogenerate: true}
      @foreign_key_type type
      @timestamps_opts [usec: false]
    end
  end
end

defmodule EctoReplaySandbox.Integration.User do
  @moduledoc """
  This module is used to test:

    * UTC Timestamps
    * Relationships

  """
  use EctoReplaySandbox.Integration.Schema

  schema "users" do
    field :name, :string
    has_many :comments, EctoReplaySandbox.Integration.Comment, foreign_key: :author_id, on_delete: :nilify_all, on_replace: :nilify
    has_many :posts, EctoReplaySandbox.Integration.Post, foreign_key: :author_id, on_delete: :nothing, on_replace: :delete
    timestamps(type: :utc_datetime)
  end
end

defmodule EctoReplaySandbox.Integration.Post do
  @moduledoc """
  This module is used to test:

    * Overall functionality
    * Overall types
    * Non-null timestamps
    * Relationships
    * Dependent callbacks

  """
  use EctoReplaySandbox.Integration.Schema
  import Ecto.Changeset

  schema "posts" do
    field :counter, :id # Same as integer
    field :title, :string
    field :text, :binary
    field :temp, :string, default: "temp", virtual: true
    field :public, :boolean, default: true
    field :cost, :decimal
    field :visits, :integer
    field :intensity, :float
    field :posted, :date
    has_many :comments, EctoReplaySandbox.Integration.Comment, on_delete: :delete_all, on_replace: :delete
    belongs_to :author, EctoReplaySandbox.Integration.User
    timestamps()
  end

  def changeset(schema, params) do
    cast(schema, params, ~w(counter title text temp public cost visits
                           intensity posted))
  end
end

defmodule EctoReplaySandbox.Integration.Comment do
  @moduledoc """
  This module is used to test:

    * Relationships
    * Dependent callbacks

  """
  use EctoReplaySandbox.Integration.Schema

  schema "comments" do
    field :text, :string
    belongs_to :post, EctoReplaySandbox.Integration.Post
    belongs_to :author, EctoReplaySandbox.Integration.User
  end

  def changeset(schema, params) do
    Ecto.Changeset.cast(schema, params, [:text])
  end
end