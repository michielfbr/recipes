defmodule Cookbook.Recipes.RecipeIngredientsTest do
  use Cookbook.DataCase

  alias Cookbook.Recipes
  alias Cookbook.Recipes.{Ingredient, RecipeIngredient}

  import Cookbook.AccountsFixtures, only: [user_scope_fixture: 0]
  import Cookbook.RecipesFixtures

  setup do
    %{scope: user_scope_fixture()}
  end

  defp ingredients(recipe) do
    Enum.map(recipe.recipe_ingredients, &{&1.position, &1.name, &1.amount})
  end

  defp ingredient_names, do: Ingredient |> Repo.all() |> Enum.map(& &1.name) |> Enum.sort()

  describe "create_recipe/2" do
    test "creates new ingredients, lowercased", %{scope: scope} do
      attrs =
        recipe_attrs(%{
          recipe_ingredients: [
            %{name: "Tomato", amount: "400 gram"},
            %{name: " red  onion", amount: "1/2"}
          ]
        })

      assert {:ok, recipe} = Recipes.create_recipe(scope, attrs)
      assert ingredients(recipe) == [{1, "tomato", "400 g"}, {2, "red onion", "½"}]
      assert ingredient_names() == ["red onion", "tomato"]

      assert [%RecipeIngredient{quantity: quantity, unit: "g"}, _] = recipe.recipe_ingredients
      assert Decimal.equal?(quantity, 400)
    end

    test "links existing ingredients by name, regardless of case", %{scope: scope} do
      tomato = ingredient_fixture("tomato")
      attrs = recipe_attrs(%{recipe_ingredients: [%{name: "TOMATO "}]})

      assert {:ok, recipe} = Recipes.create_recipe(scope, attrs)

      assert [%RecipeIngredient{ingredient_id: id, quantity: nil, unit: nil}] =
               recipe.recipe_ingredients

      assert id == tomato.id
      assert ingredient_names() == ["tomato"]
    end

    test "allows the same ingredient more than once", %{scope: scope} do
      attrs =
        recipe_attrs(%{
          recipe_ingredients: [
            %{name: "butter", amount: "100 g"},
            %{name: "Butter", amount: "1 el"}
          ]
        })

      assert {:ok, recipe} = Recipes.create_recipe(scope, attrs)
      assert ingredients(recipe) == [{1, "butter", "100 g"}, {2, "butter", "1 el"}]
      assert ingredient_names() == ["butter"]
    end

    test "drops blank rows and renumbers the rest", %{scope: scope} do
      attrs =
        recipe_attrs(%{
          recipe_ingredients: [
            %{name: ""},
            %{name: "salt", amount: " "},
            %{name: " ", amount: ""}
          ]
        })

      assert {:ok, recipe} = Recipes.create_recipe(scope, attrs)
      assert ingredients(recipe) == [{1, "salt", ""}]
    end

    test "asks about names similar to an existing ingredient", %{scope: scope} do
      ingredient_fixture("tomato")
      attrs = recipe_attrs(%{recipe_ingredients: [%{name: "tomatoes"}, %{name: "basil"}]})

      assert {:error, changeset} = Recipes.create_recipe(scope, attrs)

      assert %{recipe_ingredients: [%{name: ["did you mean tomato?"]}, %{}]} =
               errors_on(changeset)

      assert ingredient_names() == ["tomato"]
    end

    test "creates a similar ingredient once the name is confirmed", %{scope: scope} do
      ingredient_fixture("tomato")

      attrs =
        recipe_attrs(%{recipe_ingredients: [%{name: "tomatoes", confirmed_name: "Tomatoes"}]})

      assert {:ok, recipe} = Recipes.create_recipe(scope, attrs)
      assert ingredients(recipe) == [{1, "tomatoes", ""}]
      assert ingredient_names() == ["tomato", "tomatoes"]
    end

    test "doesn't create ingredients for an invalid recipe", %{scope: scope} do
      attrs = recipe_attrs(%{title: nil, recipe_ingredients: [%{name: "basil"}]})

      assert {:error, _changeset} = Recipes.create_recipe(scope, attrs)
      assert ingredient_names() == []
    end

    test "requires a name when an amount is given", %{scope: scope} do
      attrs = recipe_attrs(%{recipe_ingredients: [%{name: "", amount: "2 el"}]})

      assert {:error, changeset} = Recipes.create_recipe(scope, attrs)
      assert %{recipe_ingredients: [%{name: ["can't be blank"]}]} = errors_on(changeset)
    end

    test "suggests the total for multiplied amounts", %{scope: scope} do
      attrs = recipe_attrs(%{recipe_ingredients: [%{name: "tomatoes", amount: "1 x 400g can"}]})

      assert {:error, changeset} = Recipes.create_recipe(scope, attrs)

      assert %{recipe_ingredients: [%{amount: ["can't read this amount, did you mean 400 g?"]}]} =
               errors_on(changeset)

      assert ingredient_names() == []
    end
  end

  describe "update_recipe/3" do
    setup %{scope: scope} do
      attrs =
        recipe_attrs(%{
          recipe_ingredients: [%{name: "flour", amount: "500 g"}, %{name: "salt", amount: "1 tl"}]
        })

      %{recipe: recipe_fixture(scope, attrs)}
    end

    test "loads names and amounts for the form", %{scope: scope, recipe: recipe} do
      assert ingredients(Recipes.get_recipe!(scope, recipe.id)) ==
               [{1, "flour", "500 g"}, {2, "salt", "1 tl"}]
    end

    test "updates, renames and removes ingredients", %{scope: scope, recipe: recipe} do
      [flour, salt] = recipe.recipe_ingredients

      attrs = %{
        "recipe_ingredients" => %{
          "0" => %{"id" => flour.id, "name" => "flour", "amount" => "450g"},
          "1" => %{"id" => salt.id, "name" => "salt"},
          "2" => %{"name" => "yeast", "amount" => "7 g"}
        },
        "recipe_ingredients_drop" => ["1"]
      }

      assert {:ok, recipe} = Recipes.update_recipe(scope, recipe, attrs)
      assert ingredients(recipe) == [{1, "flour", "450 g"}, {2, "yeast", "7 g"}]
      assert hd(recipe.recipe_ingredients).id == flour.id
      assert recipe == Recipes.get_recipe!(scope, recipe.id)
      assert ingredient_names() == ["flour", "salt", "yeast"]
    end

    test "deleting the recipe keeps the ingredients", %{scope: scope, recipe: recipe} do
      assert {:ok, _} = Recipes.delete_recipe(scope, recipe)
      assert Repo.all(RecipeIngredient) == []
      assert ingredient_names() == ["flour", "salt"]
    end
  end

  describe "put_empty_last_recipe_ingredient/1" do
    test "keeps exactly one blank row at the end", %{scope: scope} do
      recipe = Recipes.new_recipe(scope)

      rows = fn attrs ->
        scope
        |> Recipes.change_recipe(recipe, %{recipe_ingredients: attrs})
        |> Recipes.put_empty_last_recipe_ingredient()
        |> Ecto.Changeset.get_assoc(:recipe_ingredients, :struct)
        |> Enum.map(& &1.name)
      end

      assert rows.([]) == [nil]
      assert rows.([%{name: "salt"}]) == ["salt", nil]
      assert rows.([%{name: "salt"}, %{name: ""}, %{name: ""}]) == ["salt", nil]
    end
  end
end
