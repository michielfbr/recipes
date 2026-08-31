defmodule MyRecipeBook.Recipes do
  @moduledoc """
  The Recipes context.
  """

  import Ecto.Query, warn: false
  alias MyRecipeBook.Repo

  alias MyRecipeBook.Recipes.Recipe
  alias MyRecipeBook.Accounts.Scope

  @doc """
  Subscribes to scoped notifications about any recipe changes.

  The broadcasted messages match the pattern:

    * {:created, %Recipe{}}
    * {:updated, %Recipe{}}
    * {:deleted, %Recipe{}}

  """
  def subscribe_recipes(%Scope{} = scope) do
    key = scope.user.id

    Phoenix.PubSub.subscribe(MyRecipeBook.PubSub, "user:#{key}:recipes")
  end

  defp broadcast_recipe(%Scope{} = scope, message) do
    key = scope.user.id

    Phoenix.PubSub.broadcast(MyRecipeBook.PubSub, "user:#{key}:recipes", message)
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
end
