defmodule CookbookWeb.RecipeImportUrlLiveTest do
  use CookbookWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Cookbook.AI.OpenRouter
  alias Cookbook.Recipes
  alias Cookbook.Recipes.Import.Fetcher

  @moduletag :capture_log

  @recipe %{
    "found" => true,
    "title" => "Groentepaella",
    "cooking_time_minutes" => 45,
    "ingredients" => [%{"name" => "ui", "amount" => "1"}],
    "steps" => ["Snipper de ui."]
  }

  @dekrat File.read!("test/support/fixtures/recipe_pages/dekrat.html")
  @url "https://www.dekrat.nl/recept/paella?utm_source=nieuwsbrief&utm_medium=email"
  @clean_url "https://www.dekrat.nl/recept/paella"

  setup :register_and_log_in_user

  defp stub_page(status \\ 200, html \\ @dekrat) do
    Req.Test.stub(Fetcher, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("text/html")
      |> Plug.Conn.send_resp(status, html)
    end)
  end

  # Replies only once the test sends `:reply`, so the test can look at the
  # page while the recipe is being read.
  defp stub_recipe(opts \\ []) do
    test_pid = self()

    Req.Test.stub(OpenRouter, fn conn ->
      if opts[:wait] do
        send(test_pid, {:reading, self()})
        assert_receive :reply, 1_000
      end

      Req.Test.json(conn, %{
        "choices" => [
          %{"finish_reason" => "stop", "message" => %{"content" => Jason.encode!(@recipe)}}
        ]
      })
    end)
  end

  defp import_path(url), do: ~p"/recipes/import?#{[url: url]}"

  test "reads the page, then shows the filled form with the cleaned URL as source", %{conn: conn} do
    stub_page()
    stub_recipe(wait: true)

    {:ok, view, _html} = live(conn, import_path(@url))

    assert_receive {:reading, stub_pid}
    assert has_element?(view, "#import-reading", "Reading recipe from www.dekrat.nl")
    refute has_element?(view, "#recipe-form")
    refute has_element?(view, "#import-text-form")

    send(stub_pid, :reply)
    render_async(view)

    refute has_element?(view, "#import-url")
    assert has_element?(view, ~s(#recipe_title[value="Groentepaella"]))
    assert has_element?(view, ~s(#recipe_source[value="#{@clean_url}"]))
  end

  test "saving creates the recipe with the URL without utm_ parameters", %{
    conn: conn,
    scope: scope
  } do
    stub_page()
    stub_recipe()

    {:ok, view, _html} = live(conn, import_path(@url))
    render_async(view)

    assert {:ok, _index_live, _html} =
             view
             |> form("#recipe-form")
             |> render_submit()
             |> follow_redirect(conn, ~p"/recipes")

    assert [recipe] = Recipes.list_recipes(scope)
    assert recipe.title == "Groentepaella"
    assert recipe.source == @clean_url
  end

  test "a blocked site shows a message with a way to paste the text", %{conn: conn} do
    stub_page(403, "Access Denied")

    {:ok, view, _html} = live(conn, import_path("https://www.ah.nl/allerhande/recept/R-R123"))
    render_async(view)

    assert has_element?(view, "#import-error", "This site doesn't allow importing.")
    assert has_element?(view, "#import-error", "www.ah.nl")
    assert has_element?(view, ~s(#import-paste-text[href="/recipes/import"]))
    assert has_element?(view, ~s(#import-start-from-scratch[href="/recipes/new"]))
    refute has_element?(view, "#import-reading")
    refute has_element?(view, "#recipe-form")
  end

  test "Paste text instead goes to the text import", %{conn: conn} do
    stub_page(403, "Access Denied")

    {:ok, view, _html} = live(conn, import_path("https://www.ah.nl/allerhande/recept/R-R123"))
    render_async(view)

    assert {:ok, text_view, _html} =
             view
             |> element("#import-paste-text")
             |> render_click()
             |> follow_redirect(conn, ~p"/recipes/import")

    assert has_element?(text_view, "#import-text-form")
  end

  test "an invalid URL shows a message without fetching", %{conn: conn} do
    Req.Test.stub(Fetcher, fn _conn -> flunk("should not fetch") end)

    {:ok, view, _html} = live(conn, import_path("not a url"))

    assert has_element?(view, "#import-error", "That doesn't look like a web address.")
    refute has_element?(view, "#import-reading")
  end

  test "a page without a recipe shows a message", %{conn: conn} do
    stub_page(200, "<html><body><nav>Menu</nav><main>Welkom</main></body></html>")

    {:ok, view, _html} = live(conn, import_path("https://example.com/"))
    render_async(view)

    assert has_element?(view, "#import-error", "No recipe found on this page.")
  end

  test "an unreachable page shows a message", %{conn: conn} do
    stub_page(404, "Not found")

    {:ok, view, _html} = live(conn, import_path("https://example.com/weg"))
    render_async(view)

    assert has_element?(view, "#import-error", "Couldn't open this page.")
  end
end
