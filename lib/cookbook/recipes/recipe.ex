defmodule Cookbook.Recipes.Recipe do
  use Ecto.Schema
  import Ecto.Changeset
  alias Cookbook.Accounts.User
  alias Cookbook.Recipes.RecipeIngredient
  alias Cookbook.Recipes.Recipe.Step

  schema "recipes" do
    field :title, :string
    field :source, :string
    embeds_many :steps, Step, on_replace: :delete

    has_many :recipe_ingredients, RecipeIngredient,
      on_replace: :delete,
      preload_order: [asc: :position]

    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(recipe, attrs, user_scope) do
    recipe
    |> cast(attrs, [:title, :source])
    |> cast_embed(:steps, required: true, with: &Step.changeset/3)
    |> cast_assoc(:recipe_ingredients,
      with: &RecipeIngredient.changeset/3,
      drop_param: :recipe_ingredients_drop
    )
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

  @doc """
  Makes sure the ingredients end with exactly one blank row, like
  `put_empty_last_step/1`.
  """
  def put_empty_last_ingredient(%Ecto.Changeset{} = changeset) do
    rows = ingredient_rows(changeset)

    {trailing_blank, filled} =
      rows |> Enum.reverse() |> Enum.split_while(&RecipeIngredient.blank?/1)

    case trailing_blank do
      [_one] ->
        changeset

      [] ->
        put_assoc(changeset, :recipe_ingredients, rows ++ [%RecipeIngredient{}])

      more ->
        put_assoc(changeset, :recipe_ingredients, Enum.reverse(filled, [List.last(more)]))
    end
  end

  @doc """
  Drops blank ingredient rows and renumbers the remaining ones.
  """
  def drop_empty_ingredients(%Ecto.Changeset{} = changeset) do
    rows = ingredient_rows(changeset)

    case Enum.reject(rows, &RecipeIngredient.blank?/1) do
      ^rows ->
        changeset

      kept ->
        renumbered =
          kept |> Enum.with_index(1) |> Enum.map(fn {row, no} -> change(row, position: no) end)

        put_assoc(changeset, :recipe_ingredients, renumbered)
    end
  end

  @doc """
  The ingredient row changesets, without the ones being removed.
  """
  def ingredient_rows(%Ecto.Changeset{} = changeset) do
    changeset
    |> get_assoc(:recipe_ingredients)
    |> Enum.reject(&(&1.action in [:replace, :delete]))
  end

  defp blank?(nil), do: true
  defp blank?(instructions), do: String.trim(instructions) == ""
end
