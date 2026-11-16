defmodule CookbookWeb.RecipeLive.Show do
  use CookbookWeb, :live_view

  alias Cookbook.Recipes

  on_mount CookbookWeb.RecipeLive.LoadRecipe

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Recipe {@recipe.id}
        <:actions>
          <.button navigate={~p"/recipes"}>
            <.icon name="hero-arrow-left" />
          </.button>
          <.button variant="primary" navigate={~p"/recipes/#{@recipe}/edit?return_to=show"}>
            <.icon name="hero-pencil-square" /> Edit recipe
          </.button>
        </:actions>
      </.header>

      <h2>{@recipe.title}</h2>
      <ul :if={@recipe.recipe_ingredients != []} id="recipe-ingredients" class="my-4 space-y-1">
        <li
          :for={ri <- @recipe.recipe_ingredients}
          id={"recipe-ingredient-#{ri.id}"}
          class="flex gap-3"
        >
          <span class="w-24 shrink-0 text-right tabular-nums text-base-content/70">{ri.amount}</span>
          <span>{ri.name}</span>
        </li>
      </ul>
      <%= for step <- @recipe.steps do %>
        <h4>Step {step.no}</h4>
        <p>{step.instructions}</p>
      <% end %>
      <p>Source: {@recipe.source}</p>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Recipes.subscribe_recipes(socket.assigns.current_scope)
    end

    socket |> assign(:page_title, "Show Recipe") |> ok()
  end

  @impl true
  def handle_info(
        {:updated, %Cookbook.Recipes.Recipe{id: id} = recipe},
        %{assigns: %{recipe: %{id: id}}} = socket
      ) do
    socket |> assign(:recipe, recipe) |> noreply()
  end

  def handle_info(
        {:deleted, %Cookbook.Recipes.Recipe{id: id}},
        %{assigns: %{recipe: %{id: id}}} = socket
      ) do
    socket
    |> put_flash(:error, "The current recipe was deleted.")
    |> push_navigate(to: ~p"/recipes")
    |> noreply()
  end

  def handle_info({type, %Cookbook.Recipes.Recipe{}}, socket)
      when type in [:created, :updated, :deleted] do
    noreply(socket)
  end
end
