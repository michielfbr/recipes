defmodule Cookbook.Recipes.RecipeIngredient do
  @moduledoc """
  An ingredient in a recipe, with its quantity and unit. The same ingredient
  may be in a recipe more than once.

  The form edits the virtual `name` and `amount` fields. `amount` is parsed into
  `quantity` and `unit` right away; `name` is matched to an `Ingredient` when
  the recipe is saved (see `Cookbook.Recipes.create_recipe/2`).
  """
  use Ecto.Schema
  import Ecto.Changeset
  alias Cookbook.Recipes.{Amount, Ingredient, Recipe, RecipeIngredient}

  schema "recipe_ingredients" do
    field :position, :integer
    field :quantity, :decimal
    field :unit, :string

    field :name, :string, virtual: true
    field :amount, :string, virtual: true
    # A name the user chose to add as a new ingredient, although a similar one exists.
    field :confirmed_name, :string, virtual: true

    belongs_to :recipe, Recipe
    belongs_to :ingredient, Ingredient

    timestamps(type: :utc_datetime)
  end

  @doc """
  `position` is derived from the ingredient's position in the recipe (0-based,
  as given by `cast_assoc/3`), like `Cookbook.Recipes.Recipe.Step.changeset/3`.
  """
  def changeset(%RecipeIngredient{} = recipe_ingredient, attrs, position) do
    recipe_ingredient
    |> cast(attrs, [:name, :amount, :confirmed_name])
    |> validate_name()
    |> put_position(position)
    |> put_quantity_and_unit()
  end

  # Only required once an amount is filled in, so blank rows (which are dropped
  # when saving) don't make the recipe invalid.
  defp validate_name(changeset) do
    if blank?(get_field(changeset, :name)) and not blank?(get_field(changeset, :amount)) do
      add_error(changeset, :name, "can't be blank", validation: :required)
    else
      changeset
    end
  end

  defp put_position(changeset, nil), do: changeset
  defp put_position(changeset, position), do: put_change(changeset, :position, position + 1)

  defp put_quantity_and_unit(changeset) do
    with {:ok, amount} <- fetch_change(changeset, :amount),
         {:ok, {quantity, unit}} <- Amount.parse(amount) do
      change(changeset, quantity: quantity, unit: unit)
    else
      :error -> changeset
      {:error, {message, opts}} -> add_error(changeset, :amount, message, opts)
    end
  end

  @doc """
  Fills the virtual `name` and `amount` fields of a stored recipe ingredient,
  for the form. Expects the `ingredient` to be preloaded.
  """
  def put_form_fields(%RecipeIngredient{ingredient: %Ingredient{} = ingredient} = ri) do
    %{ri | name: ingredient.name, amount: Amount.format(ri.quantity, ri.unit)}
  end

  @doc """
  Whether neither a name nor an amount was filled in.
  """
  def blank?(%Ecto.Changeset{} = changeset) do
    blank?(get_field(changeset, :name)) and blank?(get_field(changeset, :amount))
  end

  def blank?(nil), do: true
  def blank?(text) when is_binary(text), do: String.trim(text) == ""
end
