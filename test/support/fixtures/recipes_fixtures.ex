defmodule Cookbook.RecipesFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Cookbook.Recipes` context.
  """

  def recipe_attrs(attrs \\ %{}) do
    Enum.into(attrs, %{
      steps: [
        %{no: 1, instructions: "some instructions"},
        %{no: 2, instructions: "even more instructions"}
      ],
      source: "some source",
      title: "some title"
    })
  end

  @doc """
  Generate a recipe.
  """
  def recipe_fixture(scope, attrs \\ %{}) do
    attrs = recipe_attrs(attrs)

    {:ok, recipe} = Cookbook.Recipes.create_recipe(scope, attrs)
    recipe
  end
end
