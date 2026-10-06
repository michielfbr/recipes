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

    @doc """
  Makes sure the steps end with exactly one empty step, for the form to type
  the next step in. Extra empty steps at the end are removed.
  """
  def put_empty_last_step(%Ecto.Changeset{} = changeset) do
    steps = get_field(changeset, :steps)

    {trailing_empty, filled} =
      steps |> Enum.reverse() |> Enum.split_while(&blank?(&1.instructions))

    case trailing_empty do
      [_one] ->
        changeset

      [] ->
        put_change(changeset, :steps, steps ++ [%Step{no: length(steps) + 1}])

      more ->
        put_change(changeset, :steps, Enum.reverse(filled, [List.last(more)]))
    end
  end

  @doc """
  Drops steps without instructions and renumbers the remaining ones.

  When every step is empty they are kept, so the form still
  shows a step next to the error.
  """
  def drop_empty_steps(%Ecto.Changeset{} = changeset) do
    steps = get_field(changeset, :steps)

    case Enum.reject(steps, &blank?(&1.instructions)) do
      [] ->
        add_error(changeset, :steps, "needs at least one step")

      ^steps ->
        changeset

      kept ->
        renumbered = kept |> Enum.with_index(1) |> Enum.map(fn {step, no} -> %{step | no: no} end)
        put_embed(changeset, :steps, renumbered)
    end
  end



  defp blank?(nil), do: true
  defp blank?(instructions), do: String.trim(instructions) == ""
end
