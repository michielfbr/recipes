defmodule MyRecipeBook.Recipes.Recipe.Step do
  use Ecto.Schema
  import Ecto.Changeset
  alias MyRecipeBook.Recipes.Recipe.Step

  @primary_key false

  embedded_schema do
    field :no, :integer
    field :instructions, :string
  end

  @doc """
  `no` is derived from the step's position in the recipe's step list (0-based,
  as given by `cast_embed/3`), so steps are always numbered consecutively.
  """
  def changeset(%Step{} = step, attrs, position) do
    step
    |> cast(attrs, [:instructions])
    |> put_no(position)
  end

  defp put_no(changeset, nil), do: changeset
  defp put_no(changeset, position), do: put_change(changeset, :no, position + 1)
end
