defmodule Cookbook.Recipes.IngredientsTest do
  use Cookbook.DataCase

  alias Cookbook.Recipes
  alias Cookbook.Recipes.Ingredient

  import Cookbook.AccountsFixtures, only: [user_scope_fixture: 0]
  import Cookbook.RecipesFixtures

  doctest Ingredient, only: [normalize_name: 1]

  describe "Ingredient.changeset/2" do
    test "stores the name trimmed, with single spaces and lowercased" do
      assert ingredient_fixture("  Red   ONION ").name == "red onion"
    end

    test "requires a name" do
      changeset = Ingredient.changeset(%Ingredient{}, %{name: "  "})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "names are unique, regardless of case" do
      ingredient_fixture("tomato")

      assert {:error, changeset} =
               %Ingredient{} |> Ingredient.changeset(%{name: "Tomato"}) |> Repo.insert()

      assert %{name: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "search_ingredients/2" do
    setup do
      for name <- ~w(tomato tomatoes onion salt malt) ++ ["red onion", "sweet potato"] do
        ingredient_fixture(name)
      end

      %{scope: user_scope_fixture()}
    end

    defp search(scope, term), do: scope |> Recipes.search_ingredients(term) |> Enum.map(& &1.name)

    test "ranks exact, prefix and word prefix matches first", %{scope: scope} do
      assert search(scope, "onion") == ["onion", "red onion"]
      assert search(scope, "tom") == ["tomato", "tomatoes"]
      assert search(scope, "pot") == ["sweet potato"]
    end

    test "finds names containing the term", %{scope: scope} do
      assert scope |> search("ato") |> Enum.sort() == ["sweet potato", "tomato", "tomatoes"]
    end

    test "is case and whitespace insensitive", %{scope: scope} do
      assert search(scope, " RED  onion") == ["red onion"]
    end

    test "finds similar names, to catch typos", %{scope: scope} do
      assert ["tomato" | _] = search(scope, "tomaot")
    end

    test "does not match short, different names", %{scope: scope} do
      assert search(scope, "salt") == ["salt"]
    end

    test "returns nothing for a blank term", %{scope: scope} do
      assert search(scope, " ") == []
    end
  end
end
