defmodule CookbookWeb.RecipeLive.LoadRecipe do
  @moduledoc """
  Loads the recipe from the `"id"` route param into `@recipe` for the current
  user. When it can't be found, the LiveView is halted and the user is sent back
  to the recipe listing with an error flash.

  Routes without an `"id"` param (like `/recipes/new`) are left alone.

      on_mount CookbookWeb.RecipeLive.LoadRecipe
  """
  use CookbookWeb, :verified_routes

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3, push_navigate: 2]

  alias Cookbook.Recipes

  def on_mount(:default, %{"id" => id}, _session, socket) do
    case Recipes.get_recipe(socket.assigns.current_scope, id) do
      nil ->
        {:halt,
         socket
         |> put_flash(:error, "Recipe not found")
         |> push_navigate(to: ~p"/recipes")}

      recipe ->
        {:cont, assign(socket, :recipe, recipe)}
    end
  end

  def on_mount(:default, _params, _session, socket), do: {:cont, socket}
end
