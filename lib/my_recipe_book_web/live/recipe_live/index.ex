defmodule MyRecipeBookWeb.RecipeLive.Index do
  use MyRecipeBookWeb, :live_view

  alias MyRecipeBook.Recipes

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Listing Recipes
        <:actions>
          <.button variant="primary" navigate={~p"/recipes/new"}>
            <.icon name="hero-plus" /> New Recipe
          </.button>
        </:actions>
      </.header>

      <.table
        id="recipes"
        rows={@streams.recipes}
        row_click={fn {_id, recipe} -> JS.navigate(~p"/recipes/#{recipe}") end}
      >
        <:col :let={{_id, recipe}} label="Title">{recipe.title}</:col>
        <:action :let={{_id, recipe}}>
          <div class="sr-only">
            <.link navigate={~p"/recipes/#{recipe}"}>Show</.link>
          </div>
          <.link navigate={~p"/recipes/#{recipe}/edit"}>Edit</.link>
        </:action>
        <:action :let={{id, recipe}}>
          <.link
            phx-click={JS.push("delete", value: %{id: recipe.id}) |> hide("##{id}")}
            data-confirm="Are you sure?"
          >
            Delete
          </.link>
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
    |> assign(:page_title, "Listing Recipes")
    |> stream(:recipes, list_recipes(socket.assigns.current_scope))
    |> ok()
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    recipe = Recipes.get_recipe!(socket.assigns.current_scope, id)
    {:ok, _} = Recipes.delete_recipe(socket.assigns.current_scope, recipe)

    socket |> stream_delete(:recipes, recipe) |> noreply()
  end

  @impl true
  def handle_info({type, %MyRecipeBook.Recipes.Recipe{}}, socket)
      when type in [:created, :updated, :deleted] do
    socket
    |> stream(:recipes, list_recipes(socket.assigns.current_scope), reset: true)
    |> noreply()
  end

  defp list_recipes(current_scope) do
    Recipes.list_recipes(current_scope)
  end
end
