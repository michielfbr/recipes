defmodule Cookbook.RecipesTest do
  use Cookbook.DataCase

  alias Cookbook.Recipes

  describe "recipes" do
    alias Cookbook.Recipes.Recipe

    import Cookbook.AccountsFixtures, only: [user_scope_fixture: 0]
    import Cookbook.RecipesFixtures

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

    test "change_recipe/3 numbers steps by their position, ignoring the given no" do
      scope = user_scope_fixture()
      recipe = recipe_fixture(scope)

      changeset =
        Recipes.change_recipe(scope, recipe, %{
          steps: %{
            "0" => %{no: 1, instructions: "first"},
            "2" => %{no: 3, instructions: "third"}
          }
        })

      assert [{1, "first"}, {2, "third"}] =
               changeset
               |> Ecto.Changeset.get_field(:steps)
               |> Enum.map(&{&1.no, &1.instructions})
    end

    test "put_empty_last_recipe_step/1 adds step 1 to a recipe without steps" do
      scope = user_scope_fixture()
      recipe = %Recipe{user_id: scope.user.id, steps: []}

      changeset = scope |> Recipes.change_recipe(recipe) |> Recipes.put_empty_last_recipe_step()

      assert [%Recipe.Step{no: 1}] = Ecto.Changeset.get_field(changeset, :steps)
    end

    test "put_empty_last_recipe_step/1 appends an empty step after a filled in last step" do
      scope = user_scope_fixture()
      recipe = recipe_fixture(scope)

      changeset =
        scope
        |> Recipes.change_recipe(recipe, %{title: nil})
        |> Recipes.put_empty_last_recipe_step()

      assert [{1, _}, {2, _}, {3, nil}] = steps(changeset)
    end

    test "put_empty_last_recipe_step/1 keeps a single empty last step" do
      scope = user_scope_fixture()
      recipe = recipe_fixture(scope)

      changeset =
        scope
        |> Recipes.change_recipe(recipe, %{
          steps: [%{instructions: "first"}, %{instructions: " "}]
        })
        |> Recipes.put_empty_last_recipe_step()

      assert [{1, "first"}, {2, nil}] = steps(changeset)
    end

    test "put_empty_last_recipe_step/1 collapses empty last steps into one" do
      scope = user_scope_fixture()
      recipe = recipe_fixture(scope)

      changeset =
        scope
        |> Recipes.change_recipe(recipe, %{
          steps: [
            %{instructions: ""},
            %{instructions: "second"},
            %{instructions: ""},
            %{instructions: ""}
          ]
        })
        |> Recipes.put_empty_last_recipe_step()

      assert [{1, nil}, {2, "second"}, {3, nil}] = steps(changeset)
    end

    test "change_recipe/3 keeps empty steps while editing" do
      scope = user_scope_fixture()
      recipe = recipe_fixture(scope)

      changeset =
        Recipes.change_recipe(scope, recipe, %{
          steps: [%{instructions: "first"}, %{instructions: ""}]
        })

      assert changeset.valid?
      assert [1, 2] = changeset |> Ecto.Changeset.get_field(:steps) |> Enum.map(& &1.no)
    end

    test "create_recipe/2 drops empty steps and renumbers the rest" do
      scope = user_scope_fixture()

      attrs =
        recipe_attrs(%{
          steps: [
            %{instructions: "first"},
            %{instructions: ""},
            %{instructions: "   "},
            %{instructions: "fourth"}
          ]
        })

      assert {:ok, %Recipe{} = recipe} = Recipes.create_recipe(scope, attrs)
      assert [{1, "first"}, {2, "fourth"}] = Enum.map(recipe.steps, &{&1.no, &1.instructions})
    end

    test "create_recipe/2 with only empty steps returns an error on steps" do
      scope = user_scope_fixture()
      attrs = recipe_attrs(%{steps: [%{instructions: ""}, %{instructions: " "}]})

      assert {:error, changeset} = Recipes.create_recipe(scope, attrs)
      assert %{steps: ["needs at least one step"]} = errors_on(changeset)
    end

    test "update_recipe/3 drops empty steps and renumbers the rest" do
      scope = user_scope_fixture()
      recipe = recipe_fixture(scope)

      attrs = %{steps: [%{instructions: ""}, %{instructions: "second"}]}

      assert {:ok, %Recipe{} = recipe} = Recipes.update_recipe(scope, recipe, attrs)
      assert [{1, "second"}] = Enum.map(recipe.steps, &{&1.no, &1.instructions})
      assert recipe == Recipes.get_recipe!(scope, recipe.id)
    end

    defp steps(changeset) do
      changeset
      |> Ecto.Changeset.get_field(:steps)
      |> Enum.map(&{&1.no, &1.instructions})
    end
  end
end
