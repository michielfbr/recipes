defmodule Cookbook.AI.OpenRouterTest do
  use ExUnit.Case, async: true

  @moduletag :capture_log

  alias Cookbook.AI.OpenRouter

  @recipe %{
    "found" => true,
    "title" => "Pannenkoeken",
    "cooking_time_minutes" => 30,
    "ingredients" => [
      %{"name" => "bloem", "amount" => "250 g"},
      %{"name" => "eieren", "amount" => "2"}
    ],
    "steps" => ["Meng alles.", "Bak de pannenkoeken."]
  }

  defp completion(content, finish_reason \\ "stop") do
    %{
      "model" => "test/model",
      "choices" => [
        %{
          "finish_reason" => finish_reason,
          "message" => %{"role" => "assistant", "content" => content}
        }
      ],
      "usage" => %{"prompt_tokens" => 100, "completion_tokens" => 50, "cost" => 0.0001}
    }
  end

  defp stub_json(body, status \\ 200) do
    Req.Test.stub(OpenRouter, fn conn ->
      conn
      |> Plug.Conn.put_status(status)
      |> Req.Test.json(body)
    end)
  end

  test "returns the extracted recipe" do
    stub_json(completion(Jason.encode!(@recipe)))

    assert {:ok, recipe} = OpenRouter.extract_recipe("Pancakes: flour, eggs...")
    assert recipe == Map.delete(@recipe, "found")
  end

  test "sends the configured model, the JSON schema and the content" do
    test_pid = self()

    Req.Test.stub(OpenRouter, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:request, conn, Jason.decode!(body)})
      Req.Test.json(conn, completion(Jason.encode!(@recipe)))
    end)

    assert {:ok, _recipe} = OpenRouter.extract_recipe("Pancakes")

    assert_receive {:request, conn, body}
    assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer test-key"]
    assert body["model"] == "test/model"
    assert body["provider"] == %{"require_parameters" => true}
    assert body["reasoning"]["effort"] == "low"

    assert %{"type" => "json_schema", "json_schema" => json_schema} = body["response_format"]
    assert json_schema["strict"] == true
    assert json_schema["schema"]["additionalProperties"] == false

    assert [%{"role" => "system"}, %{"role" => "user", "content" => [user_content]}] =
             body["messages"]

    assert user_content == %{"type" => "text", "text" => "Pancakes"}
  end

  test "the :model option overrides the configured model" do
    test_pid = self()

    Req.Test.stub(OpenRouter, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:model, Jason.decode!(body)["model"]})
      Req.Test.json(conn, completion(Jason.encode!(@recipe)))
    end)

    assert {:ok, _recipe} = OpenRouter.extract_recipe("Pancakes", model: "other/model")
    assert_receive {:model, "other/model"}
  end

  test "returns :no_recipe when the content has no recipe" do
    stub_json(completion(Jason.encode!(%{@recipe | "found" => false})))

    assert OpenRouter.extract_recipe("Just a shopping list") == {:error, :no_recipe}
  end

  test "returns :ai_failed when the response was cut off" do
    stub_json(completion(~s({"found": true, "title": "Pann), "length"))

    assert OpenRouter.extract_recipe("Pancakes") == {:error, :ai_failed}
  end

  test "returns :ai_failed when the content isn't valid JSON" do
    stub_json(completion("Sorry, I can't help with that."))

    assert OpenRouter.extract_recipe("Pancakes") == {:error, :ai_failed}
  end

  test "returns :no_credits on HTTP 402" do
    stub_json(%{"error" => %{"message" => "Insufficient credits"}}, 402)

    assert OpenRouter.extract_recipe("Pancakes") == {:error, :no_credits}
  end

  test "returns :ai_unavailable on HTTP 503" do
    stub_json(%{"error" => %{"message" => "Unavailable"}}, 503)

    assert OpenRouter.extract_recipe("Pancakes") == {:error, :ai_unavailable}
  end

  test "returns :ai_unavailable on HTTP 429" do
    stub_json(%{"error" => %{"message" => "Rate limited"}}, 429)

    assert OpenRouter.extract_recipe("Pancakes") == {:error, :ai_unavailable}
  end

  test "returns :ai_unavailable when the connection fails" do
    Req.Test.stub(OpenRouter, &Req.Test.transport_error(&1, :econnrefused))

    assert OpenRouter.extract_recipe("Pancakes") == {:error, :ai_unavailable}
  end
end
