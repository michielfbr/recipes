defmodule Cookbook.Recipes.Import do
  @moduledoc """
  Imports a recipe from outside the app. The result is form params for the
  recipe form, so the user can review the recipe before saving it.
  """

  alias Cookbook.Accounts.Scope
  alias Cookbook.AI.OpenRouter

  @max_text_length 15_000

  @type error :: :empty | OpenRouter.error()

  @doc """
  Reads a recipe from pasted text and translates it to Dutch.

  Text longer than #{@max_text_length} characters is cut off.

  Returns `{:ok, params}` with params in the shape the recipe form submits,
  ready for `Cookbook.Recipes.change_recipe/3`.
  """
  @spec from_text(%Scope{}, String.t()) :: {:ok, map()} | {:error, error()}
  def from_text(%Scope{}, text) when is_binary(text) do
    text |> String.trim() |> from_trimmed_text()
  end

  defp from_trimmed_text(""), do: {:error, :empty}

  defp from_trimmed_text(text) do
    with {:ok, recipe} <-
           text |> String.slice(0, @max_text_length) |> OpenRouter.extract_recipe() do
      {:ok, to_params(recipe)}
    end
  end

  defp to_params(recipe) do
    %{
      "title" => recipe["title"],
      "cooking_time" => recipe["cooking_time_minutes"],
      "steps" => Enum.map(recipe["steps"], &%{"instructions" => &1}),
      "recipe_ingredients" =>
        Enum.map(recipe["ingredients"], &%{"name" => &1["name"], "amount" => &1["amount"]})
    }
  end
end
