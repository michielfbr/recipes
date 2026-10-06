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
    |> cast_embed(:steps, required: true, with: &Step.changeset/3)
    |> validate_required([:title])
    |> put_change(:user_id, user_scope.user.id)
  end

  def add_step(%Ecto.Changeset{} = changeset) do
    if steps_valid?(changeset) do
      steps = get_field(changeset, :steps)

      put_change(changeset, :steps, steps ++ [%Step{no: length(steps) + 1}])
    else
      changeset
    end
  end

  # Only looks at the individual steps, so errors on other fields (or the
  # required error on an empty step list) don't block adding a step.
  # Steps removed through `on_replace: :delete` show up with action :replace.
  defp steps_valid?(changeset) do
    changeset
    |> get_change(:steps, [])
    |> Enum.reject(&(&1.action == :replace))
    |> Enum.all?(& &1.valid?)
  end
end
