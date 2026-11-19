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
          <.button
            id="new-recipe"
            variant="primary"
            phx-click={show_modal("new-recipe-modal")}
          >
            <.icon name="hero-plus" /> New
          </.button>
        </:actions>
      </.header>

      <.modal id="new-recipe-modal" title="New recipe">
        <:subtitle>How do you want to start?</:subtitle>
        <div class="flex flex-col gap-3">
          <.new_recipe_option
            id="new-from-text"
            navigate={~p"/recipes/import"}
            icon="hero-clipboard-document-list"
            title="From text"
          >
            Paste a recipe from a website, email or note. It's translated to Dutch for you.
          </.new_recipe_option>
          <.new_recipe_option
            id="new-from-scratch"
            navigate={~p"/recipes/new"}
            icon="hero-pencil-square"
            title="From scratch"
          >
            Start with an empty recipe.
          </.new_recipe_option>
        </div>
      </.modal>

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

  attr :id, :string, required: true
  attr :navigate, :string, required: true
  attr :icon, :string, required: true
  attr :title, :string, required: true
  slot :inner_block, required: true

  defp new_recipe_option(assigns) do
    ~H"""
    <.link
      id={@id}
      navigate={@navigate}
      class="group flex items-center gap-4 rounded-xl border border-base-300 p-4 transition duration-200 hover:-translate-y-0.5 hover:border-primary/50 hover:bg-primary/5 hover:shadow-md focus-visible:outline-2 focus-visible:outline-primary"
    >
      <span class="flex size-11 shrink-0 items-center justify-center rounded-lg bg-primary/10 text-primary transition group-hover:bg-primary group-hover:text-primary-content">
        <.icon name={@icon} class="size-6" />
      </span>
      <span class="min-w-0 flex-1">
        <span class="block font-medium">{@title}</span>
        <span class="block text-sm text-base-content/70">{render_slot(@inner_block)}</span>
      </span>
      <.icon
        name="hero-chevron-right"
        class="size-5 text-base-content/40 transition group-hover:translate-x-0.5 group-hover:text-primary"
      />
    </.link>
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
