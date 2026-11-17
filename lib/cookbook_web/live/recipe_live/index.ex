defmodule CookbookWeb.RecipeLive.Index do
  use CookbookWeb, :live_view

  alias Cookbook.Recipes

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Recipes
        <:actions>
          <.button variant="primary" navigate={~p"/recipes/new"}>
            <.icon name="hero-plus" /> New
          </.button>
        </:actions>
      </.header>

      <.table
        id="recipes"
        rows={@streams.recipes}
        row_click={fn {_id, recipe} -> JS.navigate(~p"/recipes/#{recipe}") end}
      >
        <:col :let={{_id, recipe}}>{recipe.title}</:col>
        <:action :let={{_id, recipe}}>
          <div class="sr-only">
            <.link navigate={~p"/recipes/#{recipe}"}>Show</.link>
          </div>
          <.link navigate={~p"/recipes/#{recipe}/edit"}>Edit</.link>
        </:action>
      </.table>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Recipes.subscribe_recipes(socket.assigns.current_scope)
    end

    socket
    |> assign(:page_title, "Recipes")
    |> stream(:recipes, list_recipes(socket.assigns.current_scope))
    |> ok()
  end

  @impl true
  def handle_info({type, %Cookbook.Recipes.Recipe{}}, socket)
      when type in [:created, :updated, :deleted] do
    socket
    |> stream(:recipes, list_recipes(socket.assigns.current_scope), reset: true)
    |> noreply()
  end

  defp list_recipes(current_scope) do
    Recipes.list_recipes(current_scope)
  end
end
