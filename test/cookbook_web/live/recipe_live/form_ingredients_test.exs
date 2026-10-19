defmodule CookbookWeb.RecipeLive.FormIngredientsTest do
  use CookbookWeb.ConnCase

  import Phoenix.LiveViewTest
  import Cookbook.RecipesFixtures

  alias Cookbook.Recipes

  setup :register_and_log_in_user

  defp type_name(view, name, index \\ "0") do
    view
    |> form("#recipe-form", recipe: %{recipe_ingredients: %{index => %{name: name}}})
    |> render_change(%{_target: ["recipe", "recipe_ingredients", index, "name"]})
  end

  # `filled` are values the hook fills in, which aren't in the DOM yet.
  defp save(view, ingredients, filled \\ %{}) do
    view
    |> form("#recipe-form",
      recipe: %{
        title: "soup",
        steps: %{"0" => %{instructions: "cook"}},
        recipe_ingredients: ingredients
      }
    )
    |> render_submit(%{recipe: %{recipe_ingredients: filled}})
  end

  test "keeps one blank ingredient row at the end", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/recipes/new")

    assert has_element?(view, "#recipe_recipe_ingredients_0_name")
    refute has_element?(view, "#recipe-ingredient-0-remove")

    type_name(view, "salt")

    assert has_element?(view, "#recipe_recipe_ingredients_1_name")
    assert has_element?(view, "#recipe-ingredient-0-remove")
    refute has_element?(view, "#recipe-ingredient-1-remove")
  end

  describe "ingredient search" do
    setup do
      %{tomato: ingredient_fixture("tomato"), tomatoes: ingredient_fixture("tomatoes")}
    end

    test "lists matching ingredients while typing", %{conn: conn, tomato: tomato} do
      {:ok, view, _html} = live(conn, ~p"/recipes/new")

      type_name(view, "Tom")

      assert has_element?(view, "#recipe_recipe_ingredients_0_name-options[role=listbox]")

      assert has_element?(
               view,
               "#recipe_recipe_ingredients_0_name-option-#{tomato.id}[data-fill-value=tomato]"
             )
    end

    test "closes once the name matches an ingredient", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/recipes/new")

      type_name(view, "tom")
      type_name(view, "Tomato")

      refute has_element?(view, "#recipe_recipe_ingredients_0_name-options")
    end

    test "closes when nothing matches or when typing elsewhere", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/recipes/new")

      type_name(view, "basil")
      refute has_element?(view, "#recipe_recipe_ingredients_0_name-options")

      type_name(view, "tom")

      view
      |> form("#recipe-form", recipe: %{title: "soup"})
      |> render_change(%{_target: ["recipe", "title"]})

      refute has_element?(view, "#recipe_recipe_ingredients_0_name-options")
    end

    test "closes on the hook's close event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/recipes/new")

      type_name(view, "tom")
      view |> element("#recipe-ingredients") |> render_hook("close_ingredient_search", %{})

      refute has_element?(view, "#recipe_recipe_ingredients_0_name-options")
    end

    test "only opens for the row being typed in", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/recipes/new")

      type_name(view, "salt")
      type_name(view, "tom", "1")

      refute has_element?(view, "#recipe_recipe_ingredients_0_name-options")
      assert has_element?(view, "#recipe_recipe_ingredients_1_name-options")
    end
  end

  describe "saving" do
    test "stores the ingredients with the recipe", %{conn: conn, scope: scope} do
      {:ok, view, _html} = live(conn, ~p"/recipes/new")

      assert {:error, {:live_redirect, _}} =
               save(view, %{"0" => %{name: "Leek", amount: "2 stuks"}})

      assert [recipe] = Recipes.list_recipes(scope)
      assert [%{name: "leek", amount: "2 stuk"}] = recipe.recipe_ingredients
    end

    test "asks to confirm names similar to an existing ingredient", %{conn: conn, scope: scope} do
      ingredient_fixture("tomato")
      {:ok, view, _html} = live(conn, ~p"/recipes/new")

      save(view, %{"0" => %{name: "tomatos"}})

      assert has_element?(
               view,
               "#recipe_recipe_ingredients_0_name-use-suggestion[data-fill-id=recipe_recipe_ingredients_0_name][data-fill-value=tomato]"
             )

      assert has_element?(
               view,
               "#recipe_recipe_ingredients_0_name-keep-new[data-fill-id=recipe_recipe_ingredients_0_confirmed_name][data-fill-value=tomatos][data-dispatch-id=recipe_recipe_ingredients_0_name]"
             )

      assert Recipes.list_recipes(scope) == []

      # what the keep new button fills in
      assert {:error, {:live_redirect, _}} =
               save(view, %{"0" => %{name: "tomatos"}}, %{"0" => %{confirmed_name: "tomatos"}})

      assert [%{recipe_ingredients: [%{name: "tomatos"}]}] = Recipes.list_recipes(scope)
    end

    test "suggests the total for multiplied amounts", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/recipes/new")

      save(view, %{"0" => %{name: "tomatoes", amount: "1 x 400g can"}})

      assert has_element?(
               view,
               "#recipe_recipe_ingredients_0_amount-use-suggestion[data-fill-value='400 g']"
             )
    end
  end

  describe "editing" do
    setup %{scope: scope} do
      attrs =
        recipe_attrs(%{
          recipe_ingredients: [%{name: "flour", amount: "500 g"}, %{name: "salt", amount: "1 tl"}]
        })

      %{recipe: recipe_fixture(scope, attrs)}
    end

    test "shows the ingredients", %{conn: conn, recipe: recipe} do
      {:ok, view, _html} = live(conn, ~p"/recipes/#{recipe}/edit")

      assert has_element?(view, "#recipe_recipe_ingredients_0_name[value=flour]")
      assert has_element?(view, "#recipe_recipe_ingredients_1_amount[value='1 tl']")
      assert has_element?(view, "#recipe_recipe_ingredients_2_name")
    end

    test "removes an ingredient", %{conn: conn, scope: scope, recipe: recipe} do
      {:ok, view, _html} = live(conn, ~p"/recipes/#{recipe}/edit")

      view
      |> form("#recipe-form", recipe: %{recipe_ingredients_drop: ["0"]})
      |> render_change()

      # Input ids stay the same for a row (see `_persistent_id`), names follow the position.
      assert has_element?(view, "input[name='recipe[recipe_ingredients][0][name]'][value=salt]")
      refute has_element?(view, "input[name='recipe[recipe_ingredients][2][name]']")

      assert {:error, {:live_redirect, _}} = view |> form("#recipe-form") |> render_submit()
      assert [%{name: "salt"}] = Recipes.get_recipe!(scope, recipe.id).recipe_ingredients
    end
  end
end
