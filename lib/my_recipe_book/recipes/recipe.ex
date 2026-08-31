defmodule MyRecipeBook.Recipes.Recipe do
  use Ecto.Schema
  import Ecto.Changeset
  alias MyRecipeBook.Accounts.User

  schema "recipes" do
    field :title, :string
    field :source, :string
    embeds_many :steps, MyRecipeBook.Recipes.Recipe.Step, on_replace: :delete
    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(recipe, attrs, user_scope) do
    recipe
    |> cast(attrs, [:title, :source])
    |> cast_embed(:steps, required: true)
    |> validate_required([:title])
    |> put_change(:user_id, user_scope.user.id)
  end
end
