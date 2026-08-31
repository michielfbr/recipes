defmodule MyRecipeBookWeb.RecipeLiveTest do
  use MyRecipeBookWeb.ConnCase

  import Phoenix.LiveViewTest
  import MyRecipeBook.RecipesFixtures

  # `steps` is rendered with `<.inputs_for>`, so the form submits it keyed by index
  # (`recipe[steps][0][...]`) instead of as a list.
  #
  # `Recipes.new_recipe/1` seeds the new-recipe form with a single empty step, so
  # @create_attrs may only address index 0.
  @create_attrs %{
    steps: %{"0" => %{no: 1, instructions: "some instructions"}},
    source: "some source",
    title: "some title"
  }
  @update_attrs %{
    steps: %{
      "0" => %{no: 1, instructions: "some updated instructions"},
      "1" => %{no: 2, instructions: "even more updated instructions"}
    },
    source: "some other source",
    title: "some updated title"
  }
  @invalid_attrs %{steps: %{"0" => %{no: 1, instructions: ""}}, title: nil, source: nil}

  setup :register_and_log_in_user

  defp create_recipe(%{scope: scope}) do
    recipe = recipe_fixture(scope)

    %{recipe: recipe}
  end

  describe "Index" do
    setup [:create_recipe]

    test "lists all recipes", %{conn: conn, recipe: recipe} do
      {:ok, _index_live, html} = live(conn, ~p"/recipes")

      assert html =~ "Listing Recipes"
      assert html =~ recipe.title
    end

    test "saves new recipe", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/recipes")

      assert {:ok, form_live, _} =
               index_live
               |> element("a", "New Recipe")
               |> render_click()
               |> follow_redirect(conn, ~p"/recipes/new")

      assert render(form_live) =~ "New Recipe"

      assert form_live
             |> form("#recipe-form", recipe: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#recipe-form", recipe: @create_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/recipes")

      html = render(index_live)
      assert html =~ "Recipe created successfully"
      assert html =~ "some title"
    end

    test "updates recipe in listing", %{conn: conn, recipe: recipe} do
      {:ok, index_live, _html} = live(conn, ~p"/recipes")

      assert {:ok, form_live, _html} =
               index_live
               |> element("#recipes-#{recipe.id} a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/recipes/#{recipe}/edit")

      assert render(form_live) =~ "Edit Recipe"

      assert form_live
             |> form("#recipe-form", recipe: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#recipe-form", recipe: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/recipes")

      html = render(index_live)
      assert html =~ "Recipe updated successfully"
      assert html =~ "some updated title"
    end

    test "deletes recipe in listing", %{conn: conn, recipe: recipe} do
      {:ok, index_live, _html} = live(conn, ~p"/recipes")

      assert index_live |> element("#recipes-#{recipe.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#recipes-#{recipe.id}")
    end
  end

  describe "Show" do
    setup [:create_recipe]

    test "displays recipe", %{conn: conn, recipe: recipe} do
      {:ok, _show_live, html} = live(conn, ~p"/recipes/#{recipe}")

      assert html =~ "Show Recipe"
      assert html =~ recipe.title
    end

    test "updates recipe and returns to show", %{conn: conn, recipe: recipe} do
      {:ok, show_live, _html} = live(conn, ~p"/recipes/#{recipe}")

      assert {:ok, form_live, _} =
               show_live
               |> element("a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/recipes/#{recipe}/edit?return_to=show")

      assert render(form_live) =~ "Edit Recipe"

      assert form_live
             |> form("#recipe-form", recipe: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, show_live, _html} =
               form_live
               |> form("#recipe-form", recipe: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/recipes/#{recipe}")

      html = render(show_live)
      assert html =~ "Recipe updated successfully"
      assert html =~ "some updated title"
    end
  end
end
