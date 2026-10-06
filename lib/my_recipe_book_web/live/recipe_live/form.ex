defmodule MyRecipeBookWeb.RecipeLive.Form do
  use MyRecipeBookWeb, :live_view

  alias MyRecipeBook.Recipes

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@page_title}
        <:subtitle>Use this form to manage recipe records in your database.</:subtitle>
      </.header>

      <.form for={@form} id="recipe-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:title]} type="text" label="Title" />
        <%!-- <.input field={@form[:instructions]} type="textarea" label="Instructions --" /> --%>
        <.inputs_for :let={step} field={@form[:steps]}>
          <div class="mt-2">
            <.input
              field={step[:instructions]}
              type="textarea"
              label={"Step #{step[:no].value}"}
              step="any"
            />
          </div>
        </.inputs_for>
        <p
          :for={msg <- translate_errors(@form.errors, :steps)}
          id="recipe-steps-error"
          class="mt-1.5 flex gap-2 items-center text-sm text-error"
        >
          <.icon name="hero-exclamation-circle" class="size-5" />
          {msg}
        </p>
        <.input field={@form[:source]} type="text" label="Source" />
        <footer>
          <.button phx-disable-with="Saving..." variant="primary">Save Recipe</.button>
          <.button navigate={return_path(@current_scope, @return_to, @recipe)}>Cancel</.button>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    socket
    |> assign(:return_to, return_to(params["return_to"]))
    |> apply_action(socket.assigns.live_action, params)
    |> ok()
  end

  defp return_to("show"), do: "show"
  defp return_to(_), do: "index"

  defp apply_action(socket, :edit, %{"id" => id}) do
    recipe = Recipes.get_recipe!(socket.assigns.current_scope, id)

    socket
    |> assign(:page_title, "Edit Recipe")
    |> assign(:recipe, recipe)
    |> assign_form(Recipes.change_recipe(socket.assigns.current_scope, recipe))
  end

  defp apply_action(socket, :new, _params) do
    scope = socket.assigns.current_scope
    recipe = Recipes.new_recipe(scope)

    socket
    |> assign(:page_title, "New Recipe")
    |> assign(:recipe, recipe)
    |> assign_form(Recipes.change_recipe(scope, recipe))
  end

  @impl true
  def handle_event("validate", %{"recipe" => recipe_params}, socket) do
    %{current_scope: scope, recipe: recipe} = socket.assigns
    changeset = Recipes.change_recipe(scope, recipe, recipe_params)

    socket |> assign_form(changeset, action: :validate) |> noreply()
  end

  def handle_event("save", %{"recipe" => recipe_params}, socket) do
    save_recipe(socket, socket.assigns.live_action, recipe_params)
  end

  defp save_recipe(socket, :edit, recipe_params) do
    case Recipes.update_recipe(socket.assigns.current_scope, socket.assigns.recipe, recipe_params) do
      {:ok, recipe} ->
        socket
        |> put_flash(:info, "Recipe updated successfully")
        |> push_navigate(
          to: return_path(socket.assigns.current_scope, socket.assigns.return_to, recipe)
        )
        |> noreply()

      {:error, %Ecto.Changeset{} = changeset} ->
        socket |> assign_form(changeset) |> noreply()
    end
  end

  defp save_recipe(socket, :new, recipe_params) do
    case Recipes.create_recipe(socket.assigns.current_scope, recipe_params) do
      {:ok, recipe} ->
        socket
        |> put_flash(:info, "Recipe created successfully")
        |> push_navigate(
          to: return_path(socket.assigns.current_scope, socket.assigns.return_to, recipe)
        )
        |> noreply()

      {:error, %Ecto.Changeset{} = changeset} ->
        socket |> assign_form(changeset) |> noreply()
    end
  end

  defp assign_form(socket, changeset, opts \\ []) do
    form =
      changeset
      |> Recipes.put_empty_last_recipe_step()
      |> to_form(opts)

    assign(socket, :form, form)
  end

  defp return_path(_scope, "index", _recipe), do: ~p"/recipes"
  defp return_path(_scope, "show", recipe), do: ~p"/recipes/#{recipe}"
end
