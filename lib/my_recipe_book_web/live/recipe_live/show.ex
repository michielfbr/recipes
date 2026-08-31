defmodule MyRecipeBookWeb.RecipeLive.Show do
  use MyRecipeBookWeb, :live_view

  alias MyRecipeBook.Recipes

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
      <%= for step <- @recipe.steps do %>
        <h4>Step {step.no}</h4>
        <p>{step.instructions}</p>
      <% end %>
      <p>Source: {@recipe.source}</p>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket) do
      Recipes.subscribe_recipes(socket.assigns.current_scope)
    end

    {:ok,
     socket
     |> assign(:page_title, "Show Recipe")
     |> assign(:recipe, Recipes.get_recipe!(socket.assigns.current_scope, id))}
  end

  @impl true
  def handle_info(
        {:updated, %MyRecipeBook.Recipes.Recipe{id: id} = recipe},
        %{assigns: %{recipe: %{id: id}}} = socket
      ) do
    {:noreply, assign(socket, :recipe, recipe)}
  end

  def handle_info(
        {:deleted, %MyRecipeBook.Recipes.Recipe{id: id}},
        %{assigns: %{recipe: %{id: id}}} = socket
      ) do
    {:noreply,
     socket
     |> put_flash(:error, "The current recipe was deleted.")
     |> push_navigate(to: ~p"/recipes")}
  end

  def handle_info({type, %MyRecipeBook.Recipes.Recipe{}}, socket)
      when type in [:created, :updated, :deleted] do
    {:noreply, socket}
  end
end
