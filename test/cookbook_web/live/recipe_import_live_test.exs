defmodule CookbookWeb.RecipeImportLiveTest do
  use CookbookWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Cookbook.AI.OpenRouter
  alias Cookbook.Recipes

  @moduletag :capture_log

  @recipe %{
    "found" => true,
    "title" => "Pannenkoeken",
    "cooking_time_minutes" => 30,
    "ingredients" => [
      %{"name" => "bloem", "amount" => "250 g"},
      %{"name" => "melk", "amount" => "500 ml"}
    ],
    "steps" => ["Meng de bloem met de melk.", "Bak de pannenkoeken."]
  }

  @text "Pancakes\n\n250 g flour\n500 ml milk\n\nMix the flour with the milk. Fry the pancakes."

  setup :register_and_log_in_user

  # Replies with `recipe`, but only once the test sends `:reply`, so the test
  # can look at the page while the recipe is being read.
  defp stub_recipe(recipe, opts \\ []) do
    test_pid = self()

    Req.Test.stub(OpenRouter, fn conn ->
      if opts[:wait] do
        send(test_pid, {:reading, self()})
        assert_receive :reply, 1_000
      end

      Req.Test.json(conn, %{
        "choices" => [
          %{"finish_reason" => "stop", "message" => %{"content" => Jason.encode!(recipe)}}
        ]
      })
    end)
  end

  defp submit_text(view, text) do
    view |> form("#import-text-form", import: %{text: text}) |> render_submit()
  end

  test "shows the text area, with the button disabled until text is pasted", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/recipes/import")

    assert has_element?(view, "#import-text-form textarea[required]")
    refute has_element?(view, "#recipe-form")
    assert has_element?(view, "#import-submit[disabled]")

    view |> form("#import-text-form", import: %{text: @text}) |> render_change()

    refute has_element?(view, "#import-submit[disabled]")
  end

  test "reads the text and fills in the recipe form", %{conn: conn} do
    stub_recipe(@recipe, wait: true)
    {:ok, view, _html} = live(conn, ~p"/recipes/import")

    submit_text(view, @text)

    assert_receive {:reading, stub_pid}
    assert has_element?(view, "#import-reading")
    assert has_element?(view, "#import-submit[disabled]")

    send(stub_pid, :reply)
    render_async(view)

    refute has_element?(view, "#import-text-form")
    assert has_element?(view, "#recipe-form")
    assert has_element?(view, ~s(#recipe_title[value="Pannenkoeken"]))
    assert has_element?(view, ~s(#recipe_cooking_time[value="0:30"]))
    assert has_element?(view, "#recipe_steps_0_instructions", "Meng de bloem met de melk.")
    assert has_element?(view, ~s(#recipe_recipe_ingredients_1_name[value="melk"]))
    assert has_element?(view, ~s(#recipe_recipe_ingredients_1_amount[value="500 ml"]))
  end

  test "saving the imported recipe creates it", %{conn: conn, scope: scope} do
    stub_recipe(@recipe)
    {:ok, view, _html} = live(conn, ~p"/recipes/import")

    submit_text(view, @text)
    render_async(view)

    assert {:ok, index_live, _html} =
             view
             |> form("#recipe-form")
             |> render_submit()
             |> follow_redirect(conn, ~p"/recipes")

    assert render(index_live) =~ "Recipe created successfully"

    assert [recipe] = Recipes.list_recipes(scope)
    assert recipe.title == "Pannenkoeken"
    assert recipe.cooking_time == 30
    assert length(recipe.steps) == 2
  end

  test "keeps the text and shows a message when there is no recipe", %{conn: conn} do
    stub_recipe(%{@recipe | "found" => false})
    {:ok, view, _html} = live(conn, ~p"/recipes/import")

    submit_text(view, "Just a shopping list")
    render_async(view)

    assert has_element?(view, "#import-error", "No recipe found in this text.")
    assert has_element?(view, "#import-text-form textarea", "Just a shopping list")
    assert has_element?(view, ~s(#import-start-from-scratch[href="/recipes/new"]))
    refute has_element?(view, "#recipe-form")
  end

  test "shows a message when only whitespace is submitted", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/recipes/import")

    submit_text(view, "  \n ")
    render_async(view)

    assert has_element?(view, "#import-error", "Paste a recipe first.")
  end

  test "shows a message when the AI is unavailable", %{conn: conn} do
    Req.Test.stub(OpenRouter, fn conn ->
      conn |> Plug.Conn.put_status(503) |> Req.Test.json(%{})
    end)

    {:ok, view, _html} = live(conn, ~p"/recipes/import")

    submit_text(view, @text)
    render_async(view)

    assert has_element?(view, "#import-error", "Reading the recipe failed, try again.")
    refute has_element?(view, "#import-submit[disabled]")
  end
end
