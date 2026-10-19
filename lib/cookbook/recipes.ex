defmodule Cookbook.Recipes do
  @moduledoc """
  The Recipes context.
  """

  import Ecto.Query, warn: false
  alias Cookbook.Repo

  alias Cookbook.Recipes.{Ingredient, Recipe}
  alias Cookbook.Accounts.Scope

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
    Repo.all_by(Recipe, user_id: scope.user.id)
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
    Repo.get_by!(Recipe, id: id, user_id: scope.user.id)
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
      {:ok, id} -> Repo.get_by(Recipe, id: id, user_id: scope.user.id)
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
      steps: [%Recipe.Step{no: 1, instructions: ""}]
    }
  end

  @doc """
  Creates a recipe.

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
           |> Recipe.drop_empty_steps()
           |> Repo.insert() do
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
           |> Recipe.drop_empty_steps()
           |> Repo.update() do
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

  # `String.jaro_distance/2` from which two ingredient names are considered
  # similar, e.g. "tomaot" ~ "tomato" (0.94) and "tomato" ~ "tomatoes" (0.92).
  @similar_jaro_distance 0.9
  @search_limit 8

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
