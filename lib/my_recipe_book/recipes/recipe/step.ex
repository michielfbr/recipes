defmodule MyRecipeBook.Recipes.Recipe.Step do
  use Ecto.Schema
  import Ecto.Changeset
  alias MyRecipeBook.Recipes.Recipe.Step

  @primary_key false

  embedded_schema do
    field :no, :integer
    field :instructions, :string
  end

  @doc false
  def changeset(%Step{} = step, attrs) do
    step
    |> cast(attrs, [:no, :instructions])
    |> validate_required([:no, :instructions])
  end
end
