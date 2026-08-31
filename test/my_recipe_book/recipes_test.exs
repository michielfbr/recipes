defmodule MyRecipeBook.RecipesTest do
  use MyRecipeBook.DataCase

  alias MyRecipeBook.Recipes

  describe "recipes" do
    alias MyRecipeBook.Recipes.Recipe

    import MyRecipeBook.AccountsFixtures, only: [user_scope_fixture: 0]
    import MyRecipeBook.RecipesFixtures

    @invalid_attrs %{steps: nil, title: nil, source: nil}

    test "list_recipes/1 returns all scoped recipes" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      recipe = recipe_fixture(scope)
      other_recipe = recipe_fixture(other_scope)
      assert Recipes.list_recipes(scope) == [recipe]
      assert Recipes.list_recipes(other_scope) == [other_recipe]
    end

    test "get_recipe!/2 returns the recipe with given id" do
      scope = user_scope_fixture()
      recipe = recipe_fixture(scope)
      other_scope = user_scope_fixture()
      assert Recipes.get_recipe!(scope, recipe.id) == recipe
      assert_raise Ecto.NoResultsError, fn -> Recipes.get_recipe!(other_scope, recipe.id) end
    end

    test "create_recipe/2 with valid data creates a recipe" do
      valid_attrs = recipe_attrs()

      scope = user_scope_fixture()

      assert {:ok, %Recipe{} = recipe} = Recipes.create_recipe(scope, valid_attrs)

      assert recipe.title == "some title"
      assert recipe.source == "some source"
      assert recipe.user_id == scope.user.id

      assert Enum.map(recipe.steps, &Map.take(&1, [:no, :instructions])) == valid_attrs.steps
    end

    test "create_recipe/2 with invalid data returns error changeset" do
      scope = user_scope_fixture()
      assert {:error, %Ecto.Changeset{}} = Recipes.create_recipe(scope, @invalid_attrs)
    end

    test "update_recipe/3 with valid data updates the recipe" do
      scope = user_scope_fixture()
      recipe = recipe_fixture(scope)

      update_attrs = %{
        steps: [
          %{no: 1, instructions: "some updated instructions"},
          %{no: 2, instructions: "even more updated instructions"}
        ],
        source: "some other source",
        title: "some new title"
      }

      assert {:ok, %Recipe{} = recipe} = Recipes.update_recipe(scope, recipe, update_attrs)

      assert recipe.title == update_attrs.title
      assert recipe.source == update_attrs.source

      assert Enum.map(recipe.steps, &Map.take(&1, [:no, :instructions])) == update_attrs.steps
    end

    test "update_recipe/3 with invalid scope raises" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      recipe = recipe_fixture(scope)

      assert_raise MatchError, fn ->
        Recipes.update_recipe(other_scope, recipe, %{})
      end
    end

    test "update_recipe/3 with invalid data returns error changeset" do
      scope = user_scope_fixture()
      recipe = recipe_fixture(scope)
      assert {:error, %Ecto.Changeset{}} = Recipes.update_recipe(scope, recipe, @invalid_attrs)
      assert recipe == Recipes.get_recipe!(scope, recipe.id)
    end

    test "delete_recipe/2 deletes the recipe" do
      scope = user_scope_fixture()
      recipe = recipe_fixture(scope)
      assert {:ok, %Recipe{}} = Recipes.delete_recipe(scope, recipe)
      assert_raise Ecto.NoResultsError, fn -> Recipes.get_recipe!(scope, recipe.id) end
    end

    test "delete_recipe/2 with invalid scope raises" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      recipe = recipe_fixture(scope)
      assert_raise MatchError, fn -> Recipes.delete_recipe(other_scope, recipe) end
    end

    test "change_recipe/2 returns a recipe changeset" do
      scope = user_scope_fixture()
      recipe = recipe_fixture(scope)
      assert %Ecto.Changeset{} = Recipes.change_recipe(scope, recipe)
    end
  end
end
