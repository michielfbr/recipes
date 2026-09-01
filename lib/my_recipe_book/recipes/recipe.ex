defmodule MyRecipeBook.Recipes.Recipe do
  use Ecto.Schema
  import Ecto.Changeset
  alias MyRecipeBook.Accounts.User
  alias MyRecipeBook.Recipes.Recipe.Step

  schema "recipes" do
    field :title, :string
    field :source, :string
    embeds_many :steps, Step, on_replace: :delete
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

  def add_step(%Ecto.Changeset{valid?: true} = changeset) do
    steps = get_field(changeset, :steps)
    no = List.last(steps).no + 1

    put_change(changeset, :steps, steps ++ [%Step{no: no}])

    # changeset
  end

  def add_step(%Ecto.Changeset{} = changeset), do: changeset
end
