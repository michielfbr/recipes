defmodule Cookbook.Recipes.ImportTest do
  use Cookbook.DataCase, async: true

  import Cookbook.AccountsFixtures, only: [user_scope_fixture: 0]

  alias Cookbook.AI.OpenRouter
  alias Cookbook.Recipes
  alias Cookbook.Recipes.Import

  @moduletag :capture_log

  @recipe %{
    "found" => true,
    "title" => "Pannenkoeken",
    "cooking_time_minutes" => 30,
    "ingredients" => [
      %{"name" => "bloem", "amount" => "250 g"},
      %{"name" => "melk", "amount" => "500 ml"},
      %{"name" => "zout", "amount" => ""}
    ],
    "steps" => ["Meng de bloem met de melk.", "Bak de pannenkoeken."]
  }

  setup do
    %{scope: user_scope_fixture()}
  end

  defp stub_recipe(recipe) do
    test_pid = self()

    Req.Test.stub(OpenRouter, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      [_system, %{"content" => [%{"text" => text}]}] = Jason.decode!(body)["messages"]
      send(test_pid, {:sent_text, text})

      Req.Test.json(conn, %{
        "choices" => [
          %{"finish_reason" => "stop", "message" => %{"content" => Jason.encode!(recipe)}}
        ]
      })
    end)
  end

  describe "from_text/2" do
    test "returns form params for the recipe", %{scope: scope} do
      stub_recipe(@recipe)

      assert {:ok, params} = Import.from_text(scope, "Pancakes: 250 g flour, ...")

      assert params == %{
               "title" => "Pannenkoeken",
               "cooking_time" => 30,
               "steps" => [
                 %{"instructions" => "Meng de bloem met de melk."},
                 %{"instructions" => "Bak de pannenkoeken."}
               ],
               "recipe_ingredients" => [
                 %{"name" => "bloem", "amount" => "250 g"},
                 %{"name" => "melk", "amount" => "500 ml"},
                 %{"name" => "zout", "amount" => ""}
               ]
             }

      changeset = Recipes.change_recipe(scope, Recipes.new_recipe(scope), params)
      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :cooking_time) == 30
      assert [%{no: 1}, %{no: 2}] = Ecto.Changeset.get_field(changeset, :steps)
    end

    test "params with an unreadable amount give an amount error", %{scope: scope} do
      stub_recipe(%{@recipe | "ingredients" => [%{"name" => "bloem", "amount" => "veel 250"}]})

      assert {:ok, params} = Import.from_text(scope, "Pancakes")

      changeset = Recipes.change_recipe(scope, Recipes.new_recipe(scope), params)
      refute changeset.valid?
      assert [row] = Recipes.ingredient_rows(changeset)
      assert row.errors[:amount]
    end

    test "returns :empty for blank text without calling the AI", %{scope: scope} do
      assert Import.from_text(scope, "") == {:error, :empty}
      assert Import.from_text(scope, "  \n ") == {:error, :empty}
    end

    test "cuts long text off at 15,000 characters", %{scope: scope} do
      stub_recipe(@recipe)

      assert {:ok, _params} = Import.from_text(scope, String.duplicate("a", 20_000))
      assert_receive {:sent_text, text}
      assert String.length(text) == 15_000
    end

    test "passes AI errors through", %{scope: scope} do
      stub_recipe(%{@recipe | "found" => false})

      assert Import.from_text(scope, "A shopping list") == {:error, :no_recipe}
    end
  end
end
