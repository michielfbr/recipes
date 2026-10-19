defmodule Cookbook.Recipes do
  @moduledoc """
  The Recipes context.
  """

  import Ecto.Query, warn: false
  alias Cookbook.Repo

  alias Cookbook.Recipes.{Ingredient, Recipe, RecipeIngredient}
  alias Cookbook.Accounts.Scope

  # `String.jaro_distance/2` from which two ingredient names are considered
  # similar, e.g. "tomaot" ~ "tomato" (0.94) and "tomato" ~ "tomatoes" (0.92).
  @similar_jaro_distance 0.9
  @search_limit 8

  @doc """
  Subscribes to scoped notifications about any recipe changes.

  The broadcasted messages match the pattern:

    * {:created, %Recipe{}}
    * {:updated, %Recipe{}}
    * {:deleted, %Recipe{}}

  """
  def subscribe_recipes(%Scope{} = scope) do
    key = scope.user.id

    Phoenix.PubSub.subscribe(Cookbook.PubSub, "user:#{key}:recipes")
  end

  defp broadcast_recipe(%Scope{} = scope, message) do
    key = scope.user.id

    Phoenix.PubSub.broadcast(Cookbook.PubSub, "user:#{key}:recipes", message)
  end

  @doc """
  Returns the list of recipes.

  ## Examples

      iex> list_recipes(scope)
      [%Recipe{}, ...]

  """
  def list_recipes(%Scope{} = scope) do
    Recipe |> Repo.all_by(user_id: scope.user.id) |> preload_ingredients()
  end

  @doc """
  Gets a single recipe.

  Raises `Ecto.NoResultsError` if the Recipe does not exist.

  ## Examples

      iex> get_recipe!(scope, 123)
      %Recipe{}

      iex> get_recipe!(scope, 456)
      ** (Ecto.NoResultsError)

  """
  def get_recipe!(%Scope{} = scope, id) do
    Recipe |> Repo.get_by!(id: id, user_id: scope.user.id) |> preload_ingredients()
  end

  @doc """
  Gets a single recipe, or `nil` if it does not exist, belongs to another user
  or `id` is not a valid id (for example when it comes from the URL).

  ## Examples

      iex> get_recipe(scope, 123)
      %Recipe{}

      iex> get_recipe(scope, "abc")
      nil

  """
  def get_recipe(%Scope{} = scope, id) do
    case Ecto.Type.cast(:id, id) do
      {:ok, id} -> Recipe |> Repo.get_by(id: id, user_id: scope.user.id) |> preload_ingredients()
      :error -> nil
    end
  end

  @doc """
  Creates a recipe.

  ## Examples

      iex> create_recipe(scope, %{field: value})
      {:ok, %Recipe{}}

      iex> create_recipe(scope, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def new_recipe(%Scope{} = scope) do
    %Recipe{
      user_id: scope.user.id,
      steps: [%Recipe.Step{no: 1, instructions: ""}],
      recipe_ingredients: []
    }
  end

  @doc """
  Creates a recipe.

  Ingredients are matched by name, see `save_recipe/2`.

  ## Examples

      iex> create_recipe(scope, %{field: value})
      {:ok, %Recipe{}}

      iex> create_recipe(scope, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_recipe(%Scope{} = scope, attrs) do
    with {:ok, recipe = %Recipe{}} <-
           %Recipe{}
           |> Recipe.changeset(attrs, scope)
           |> save_recipe(&Repo.insert/1) do
      broadcast_recipe(scope, {:created, recipe})
      {:ok, recipe}
    end
  end

  @doc """
  Updates a recipe.

  ## Examples

      iex> update_recipe(scope, recipe, %{field: new_value})
      {:ok, %Recipe{}}

      iex> update_recipe(scope, recipe, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_recipe(%Scope{} = scope, %Recipe{} = recipe, attrs) do
    true = recipe.user_id == scope.user.id

    with {:ok, recipe = %Recipe{}} <-
           recipe
           |> Recipe.changeset(attrs, scope)
           |> save_recipe(&Repo.update/1) do
      broadcast_recipe(scope, {:updated, recipe})
      {:ok, recipe}
    end
  end

  @doc """
  Deletes a recipe.

  ## Examples

      iex> delete_recipe(scope, recipe)
      {:ok, %Recipe{}}

      iex> delete_recipe(scope, recipe)
      {:error, %Ecto.Changeset{}}

  """
  def delete_recipe(%Scope{} = scope, %Recipe{} = recipe) do
    true = recipe.user_id == scope.user.id

    with {:ok, recipe = %Recipe{}} <-
           Repo.delete(recipe) do
      broadcast_recipe(scope, {:deleted, recipe})
      {:ok, recipe}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking recipe changes.

  ## Examples

      iex> change_recipe(scope, recipe)
      %Ecto.Changeset{data: %Recipe{}}

  """
  def change_recipe(%Scope{} = scope, %Recipe{} = recipe, attrs \\ %{}) do
    true = recipe.user_id == scope.user.id

    Recipe.changeset(recipe, attrs, scope)
  end

  def put_empty_last_recipe_step(%Ecto.Changeset{} = changeset) do
    Recipe.put_empty_last_step(changeset)
  end

  def put_empty_last_recipe_ingredient(%Ecto.Changeset{} = changeset) do
    Recipe.put_empty_last_ingredient(changeset)
  end

  # Drops empty steps and ingredients, matches the ingredient names and saves
  # the recipe. Ingredients that don't exist yet are created in the same
  # transaction, so they're only stored when the recipe is.
  #
  # An ingredient name that isn't known but is similar to an existing one gets
  # a "did you mean" error, unless it was confirmed (see `confirmed_name`).
  defp save_recipe(changeset, save) do
    Repo.transact(fn ->
      changeset
      |> Recipe.drop_empty_steps()
      |> Recipe.drop_empty_ingredients()
      |> match_ingredients()
      |> create_new_ingredients()
      |> save.()
    end)
    |> case do
      {:ok, recipe} -> {:ok, preload_ingredients(recipe)}
      error -> error
    end
  end

  defp match_ingredients(changeset) do
    case Recipe.ingredient_rows(changeset) do
      [] ->
        changeset

      rows ->
        ingredients = Map.new(Repo.all(Ingredient), &{&1.name, &1})
        rows = Enum.map(rows, &match_ingredient(&1, ingredients))
        Ecto.Changeset.put_assoc(changeset, :recipe_ingredients, rows)
    end
  end

  defp match_ingredient(row, ingredients) do
    name = row |> Ecto.Changeset.get_field(:name) |> Ingredient.normalize_name()
    confirmed_name = Ecto.Changeset.get_field(row, :confirmed_name)

    cond do
      name in [nil, ""] ->
        row

      ingredient = ingredients[name] ->
        Ecto.Changeset.put_change(row, :ingredient_id, ingredient.id)

      Ingredient.normalize_name(confirmed_name) == name ->
        Ecto.Changeset.put_change(row, :ingredient_id, nil)

      similar = similar_ingredient(name, Map.values(ingredients)) ->
        Ecto.Changeset.add_error(row, :name, "did you mean %{suggestion}?",
          suggestion: similar.name,
          validation: :similar_ingredient
        )

      true ->
        Ecto.Changeset.put_change(row, :ingredient_id, nil)
    end
  end

  defp similar_ingredient(name, ingredients) do
    ingredients
    |> Enum.map(&{String.jaro_distance(&1.name, name), &1})
    |> Enum.filter(fn {distance, _} -> distance >= @similar_jaro_distance end)
    |> Enum.max_by(&elem(&1, 0), fn -> {nil, nil} end)
    |> elem(1)
  end

  # Only when the recipe is otherwise valid, so no ingredients are created for
  # a recipe that won't be saved.
  defp create_new_ingredients(%Ecto.Changeset{valid?: false} = changeset), do: changeset

  defp create_new_ingredients(changeset) do
    rows = Recipe.ingredient_rows(changeset)

    new_ids =
      for row <- rows,
          Ecto.Changeset.get_field(row, :ingredient_id) == nil,
          name = Ingredient.normalize_name(Ecto.Changeset.get_field(row, :name)),
          uniq: true,
          into: %{} do
        {name, insert_ingredient!(name).id}
      end

    if new_ids == %{} do
      changeset
    else
      rows =
        Enum.map(rows, fn row ->
          case Ecto.Changeset.get_field(row, :ingredient_id) do
            nil ->
              name = Ingredient.normalize_name(Ecto.Changeset.get_field(row, :name))
              Ecto.Changeset.put_change(row, :ingredient_id, Map.fetch!(new_ids, name))

            _id ->
              row
          end
        end)

      Ecto.Changeset.put_assoc(changeset, :recipe_ingredients, rows)
    end
  end

  # Returns the existing ingredient when another recipe created it meanwhile.
  defp insert_ingredient!(name) do
    %Ingredient{}
    |> Ingredient.changeset(%{name: name})
    |> Repo.insert!(on_conflict: {:replace, [:updated_at]}, conflict_target: :name)
  end

  defp preload_ingredients(recipe_or_recipes) do
    recipe_or_recipes
    |> Repo.preload([recipe_ingredients: :ingredient], force: true)
    |> put_ingredient_form_fields()
  end

  defp put_ingredient_form_fields(nil), do: nil

  defp put_ingredient_form_fields(recipes) when is_list(recipes),
    do: Enum.map(recipes, &put_ingredient_form_fields/1)

  defp put_ingredient_form_fields(%Recipe{} = recipe) do
    %{
      recipe
      | recipe_ingredients:
          Enum.map(recipe.recipe_ingredients, &RecipeIngredient.put_form_fields/1)
    }
  end

  @doc """
  Searches the ingredients (shared by all users) for the given term.

  Matches are ranked: exact, then names starting with the term, then names
  with a word starting with it, then names containing it and finally names
  similar to it (to catch typos and plurals).

  ## Examples

      iex> search_ingredients(scope, "onion")
      [%Ingredient{name: "onion"}, %Ingredient{name: "red onion"}]

  """
  def search_ingredients(%Scope{}, term) do
    case Ingredient.normalize_name(term) do
      "" ->
        []

      term ->
        Ingredient
        |> Repo.all()
        |> Enum.flat_map(fn ingredient ->
          case search_rank(ingredient.name, term) do
            nil -> []
            rank -> [{rank, ingredient}]
          end
        end)
        |> Enum.sort_by(&elem(&1, 0))
        |> Enum.take(@search_limit)
        |> Enum.map(&elem(&1, 1))
    end
  end

  defp search_rank(name, term) do
    jaro_distance = String.jaro_distance(name, term)

    tier =
      cond do
        name == term -> 0
        String.starts_with?(name, term) -> 1
        String.contains?(name, " " <> term) -> 2
        String.contains?(name, term) -> 3
        jaro_distance >= @similar_jaro_distance -> 4
        true -> nil
      end

    tier && {tier, -jaro_distance, name}
  end
end
