defmodule Cookbook.Recipes.Import do
  @moduledoc """
  Imports a recipe from outside the app. The result is form params for the
  recipe form, so the user can review the recipe before saving it.
  """

  alias Cookbook.Accounts.Scope
  alias Cookbook.AI.OpenRouter
  alias Cookbook.Recipes.Import.Extractor
  alias Cookbook.Recipes.Import.Fetcher
  alias Cookbook.Recipes.Import.URL

  @max_text_length 15_000

  @type error :: :empty | :invalid_url | Fetcher.error() | OpenRouter.error()

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

  @doc """
  Reads a recipe from a web page and translates it to Dutch.

  Tracking parameters (`utm_*`) are removed from the URL first. The cleaned
  URL is used for everything after that and returned as `"source"` in the
  params.
  """
  @spec from_url(%Scope{}, String.t()) :: {:ok, map()} | {:error, error()}
  def from_url(%Scope{}, url) when is_binary(url) do
    with {:ok, url} <- URL.clean(url),
         {:ok, html} <- Fetcher.fetch(url),
         {:ok, content} <- Extractor.extract(html),
         {:ok, recipe} <-
           content
           |> ai_input()
           |> String.slice(0, @max_text_length)
           |> OpenRouter.extract_recipe() do
      {:ok, recipe |> to_params() |> Map.put("source", url)}
    end
  end

  defp ai_input({:json_ld, recipe}), do: Jason.encode!(recipe)
  defp ai_input({_kind, text}), do: text

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
