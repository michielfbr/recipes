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
            id="new-from-website"
            icon="hero-globe-alt"
            title="From website"
            phx-click={show_url_form()}
          >
            Paste a link to a recipe. It's read and translated to Dutch for you.
          </.new_recipe_option>
          <.form
            for={@url_form}
            id="import-url-form"
            phx-submit="import_url"
            phx-hook=".FocusOnShow"
            class="hidden rounded-xl border border-primary/50 bg-primary/5 p-4 transition duration-200 ease-out starting:-translate-y-1 starting:opacity-0"
          >
            <div class="mb-3 flex items-center gap-4">
              <span class="flex size-11 shrink-0 items-center justify-center rounded-lg bg-primary text-primary-content">
                <.icon name="hero-globe-alt" class="size-6" />
              </span>
              <span class="font-medium">From website</span>
            </div>
            <.input
              field={@url_form[:url]}
              id="import-url-input"
              type="url"
              label="Link to the recipe"
              placeholder="https://"
              inputmode="url"
              autocomplete="off"
              required
            />
            <div class="mt-1 flex justify-end">
              <.button id="import-url-submit" variant="primary" phx-disable-with="Opening…">
                <.icon name="hero-arrow-down-tray" class="size-4" /> Import
              </.button>
            </div>
          </.form>
          <script :type={Phoenix.LiveView.ColocatedHook} name=".FocusOnShow">
            // JS.focus can't be used: hiding the clicked card moves the focus to
            // the body, which stops LiveView from retrying once the form is shown.
            export default {
              mounted() {
                this.el.addEventListener("phx:show-end", () => {
                  this.el.querySelector("input:not([type=hidden])")?.focus()
                })
              },
            }
          </script>
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
  attr :navigate, :string, default: nil, doc: "renders a link; without it a button"
  attr :icon, :string, required: true
  attr :title, :string, required: true
  attr :rest, :global
  slot :inner_block, required: true

  defp new_recipe_option(%{navigate: nil} = assigns) do
    ~H"""
    <button type="button" id={@id} class={option_class()} {@rest}>
      <.new_recipe_option_content icon={@icon} title={@title}>
        {render_slot(@inner_block)}
      </.new_recipe_option_content>
    </button>
    """
  end

  defp new_recipe_option(assigns) do
    ~H"""
    <.link id={@id} navigate={@navigate} class={option_class()} {@rest}>
      <.new_recipe_option_content icon={@icon} title={@title}>
        {render_slot(@inner_block)}
      </.new_recipe_option_content>
    </.link>
    """
  end

  defp option_class do
    "group flex w-full items-center gap-4 rounded-xl border border-base-300 p-4 text-left transition duration-200 hover:-translate-y-0.5 hover:border-primary/50 hover:bg-primary/5 hover:shadow-md focus-visible:outline-2 focus-visible:outline-primary"
  end

  attr :icon, :string, required: true
  attr :title, :string, required: true
  slot :inner_block, required: true

  defp new_recipe_option_content(assigns) do
    ~H"""
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
    """
  end

  defp show_url_form do
    JS.hide(to: "#new-from-website")
    # The form animates in with CSS `starting:` classes, and its
    # .FocusOnShow hook focuses the URL field.
    |> JS.show(to: "#import-url-form")
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Recipes.subscribe_recipes(socket.assigns.current_scope)
    end

    socket
    |> assign(:page_title, "Recipes")
    |> assign(:url_form, to_form(%{"url" => ""}, as: :import))
    |> stream(:recipes, list_recipes(socket.assigns.current_scope))
    |> ok()
  end

  @impl true
  def handle_event("import_url", %{"import" => %{"url" => url}}, socket) do
    case String.trim(url) do
      "" -> {:noreply, socket}
      url -> {:noreply, push_navigate(socket, to: ~p"/recipes/import?#{[url: url]}")}
    end
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
