defmodule CookbookWeb.RecipeLive.Show do
  use CookbookWeb, :live_view

  alias Cookbook.Recipes
  alias Cookbook.Recipes.CookingTime

  on_mount CookbookWeb.RecipeLive.LoadRecipe

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@recipe.title}
        <:actions>
          <.button navigate={~p"/recipes"}>
            <.icon name="hero-arrow-left" />
          </.button>
          <.button variant="primary" navigate={~p"/recipes/#{@recipe}/edit?return_to=show"}>
            <.icon name="hero-pencil-square" /> Edit
          </.button>
        </:actions>
      </.header>

      <p :if={@recipe.cooking_time} id="recipe-cooking-time" class="flex items-center gap-1.5">
        <.icon name="hero-clock" class="size-5 text-base-content/70" />
        <span class="tabular-nums">{CookingTime.format(@recipe.cooking_time)}</span>
      </p>
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
        <h4 id={"step-label-#{step.no}"} class="text-sm text-base-content/60">Step {step.no}</h4>
        <p>{step.instructions}</p>
      <% end %>
      <p>
        <span id="source-label" class="text-sm text-base-content/60">Source:</span>
        <a
          :if={source_url(@recipe.source)}
          id="source-link"
          href={source_url(@recipe.source)}
          target="_blank"
          rel="noopener noreferrer"
          class="link link-primary break-all"
        >
          {@recipe.source}
        </a>
        <span :if={!source_url(@recipe.source)}>{@recipe.source}</span>
      </p>
    </Layouts.app>
    """
  end

  # The URL to link the source to, when it looks like one.
  defp source_url("http://" <> _ = source), do: source
  defp source_url("https://" <> _ = source), do: source
  defp source_url("www." <> _ = source), do: "https://" <> source
  defp source_url(_source), do: nil

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
