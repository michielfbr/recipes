defmodule CookbookWeb.RecipeLive.Form do
  use CookbookWeb, :live_view

  alias Cookbook.Recipes
  alias Cookbook.Recipes.Ingredient

  on_mount CookbookWeb.RecipeLive.LoadRecipe

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
        <section id="recipe-ingredients" phx-hook=".IngredientRows" class="mt-2 mb-4">
          <h2 class="label mb-1">Ingredients</h2>
          <.inputs_for :let={ri} field={@form[:recipe_ingredients]}>
            <.ingredient_row
              ri={ri}
              last?={ri.index == @ingredient_count - 1}
              search={@ingredient_search}
            />
          </.inputs_for>
          <input type="hidden" name="recipe[recipe_ingredients_drop][]" />
        </section>
        <script :type={Phoenix.LiveView.ColocatedHook} name=".IngredientRows">
          // Buttons and options with `data-fill-id` put `data-fill-value` in that
          // input and trigger the form's phx-change, as if it was typed. When
          // `data-dispatch-id` is set, that input triggers the change instead.
          export default {
            mounted() {
              this.el.addEventListener("mousedown", (e) => {
                // keep the focus in the ingredient input when picking an option
                if (e.target.closest("[role=option]")) e.preventDefault()
              })
              this.el.addEventListener("click", (e) => {
                const button = e.target.closest("[data-fill-id]")
                if (button) this.fill(button)
              })
              this.el.addEventListener("focusout", (e) => {
                const combobox = e.target.closest("[data-combobox]")
                if (combobox && !combobox.contains(e.relatedTarget)) {
                  this.pushEvent("close_ingredient_search", {})
                }
              })
              this.el.addEventListener("keydown", (e) => this.navigate(e))
            },
            updated() {
              // the server resets the options, so drop highlights that no longer exist
              this.el.querySelectorAll("[aria-activedescendant]").forEach((input) => {
                const option = document.getElementById(input.getAttribute("aria-activedescendant"))
                if (option?.getAttribute("aria-selected") !== "true") {
                  input.removeAttribute("aria-activedescendant")
                }
              })
            },
            // Arrow keys move through the open search results, Enter picks the
            // highlighted one and Escape closes them.
            navigate(e) {
              const input = e.target.closest("[role=combobox]")
              const listbox = input && document.getElementById(input.getAttribute("aria-controls"))
              if (!listbox) return

              const options = Array.from(listbox.querySelectorAll("[role=option]"))
              const current = options.findIndex((o) => o.getAttribute("aria-selected") === "true")

              switch (e.key) {
                case "ArrowDown":
                case "ArrowUp": {
                  e.preventDefault()
                  const step = e.key === "ArrowDown" ? 1 : -1
                  const next = current === -1 && step === -1 ? options.length - 1 : current + step
                  this.highlight(input, options, (next + options.length) % options.length)
                  break
                }
                case "Enter":
                  if (current !== -1) {
                    e.preventDefault()
                    this.fill(options[current])
                  }
                  break
                case "Escape":
                  e.preventDefault()
                  this.pushEvent("close_ingredient_search", {})
                  break
              }
            },
            highlight(input, options, index) {
              options.forEach((option, i) => option.setAttribute("aria-selected", i === index))
              input.setAttribute("aria-activedescendant", options[index].id)
              options[index].scrollIntoView({ block: "nearest" })
            },
            fill(button) {
              const input = document.getElementById(button.dataset.fillId)
              const dispatcher = document.getElementById(button.dataset.dispatchId) || input
              input.value = button.dataset.fillValue
              dispatcher.dispatchEvent(new Event("input", { bubbles: true }))
              if (button.closest("[role=option]")) input.focus()
            },
          }
        </script>
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

  attr :ri, Phoenix.HTML.Form, required: true
  attr :last?, :boolean, required: true
  attr :search, :map, doc: "the open ingredient search, if any: `%{index: index, results: [...]}`"

  defp ingredient_row(assigns) do
    name = assigns.ri[:name]
    results = if assigns.search[:index] == assigns.ri.index, do: assigns.search.results, else: []

    assigns =
      assign(assigns,
        name: name,
        amount: assigns.ri[:amount],
        listbox_id: "#{name.id}-options",
        results: results,
        name_suggestions: suggestions(assigns.ri, :name),
        amount_suggestions: suggestions(assigns.ri, :amount)
      )

    ~H"""
    <div id={"recipe-ingredient-#{@ri.index}"} class="flex items-start gap-2">
      <.input field={@ri[:confirmed_name]} type="hidden" />
      <div class="relative flex-1" data-combobox>
        <.input
          field={@name}
          type="text"
          placeholder="Ingredient"
          autocomplete="off"
          phx-debounce="200"
          role="combobox"
          aria-autocomplete="list"
          aria-controls={@listbox_id}
          aria-expanded={to_string(@results != [])}
        />
        <ul
          :if={@results != []}
          id={@listbox_id}
          role="listbox"
          class="absolute inset-x-0 top-11 z-10 max-h-60 overflow-auto rounded-box border border-base-300 bg-base-100 py-1 shadow-lg"
        >
          <li
            :for={ingredient <- @results}
            id={"#{@name.id}-option-#{ingredient.id}"}
            role="option"
            aria-selected="false"
            data-fill-id={@name.id}
            data-fill-value={ingredient.name}
            class="cursor-pointer px-3 py-2 text-sm transition-colors hover:bg-base-200 aria-selected:bg-primary aria-selected:text-primary-content"
          >
            {ingredient.name}
          </li>
        </ul>
        <div :for={suggestion <- @name_suggestions} class="-mt-1 mb-2 flex flex-wrap gap-2">
          <button
            type="button"
            id={"#{@name.id}-use-suggestion"}
            class="btn btn-xs btn-primary"
            data-fill-id={@name.id}
            data-fill-value={suggestion}
          >
            Use {suggestion}
          </button>
          <button
            type="button"
            id={"#{@name.id}-keep-new"}
            class="btn btn-xs btn-ghost"
            data-fill-id={@ri[:confirmed_name].id}
            data-fill-value={@name.value}
            data-dispatch-id={@name.id}
          >
            Add "{@name.value}" as new ingredient
          </button>
        </div>
      </div>
      <div class="w-36">
        <.input field={@amount} type="text" placeholder="250 g" phx-debounce="200" />
        <button
          :for={suggestion <- @amount_suggestions}
          type="button"
          id={"#{@amount.id}-use-suggestion"}
          class="btn btn-xs btn-primary -mt-1 mb-2"
          data-fill-id={@amount.id}
          data-fill-value={suggestion}
        >
          Use {suggestion}
        </button>
      </div>
      <label
        :if={not @last?}
        id={"recipe-ingredient-#{@ri.index}-remove"}
        class="btn btn-ghost btn-square text-base-content/60 transition hover:text-error"
        title="Remove ingredient"
      >
        <input
          type="checkbox"
          name="recipe[recipe_ingredients_drop][]"
          value={@ri.index}
          class="hidden"
        />
        <.icon name="hero-x-mark" class="size-5" />
      </label>
      <span :if={@last?} class="w-10 shrink-0"></span>
    </div>
    """
  end

  # The values suggested by "did you mean" errors on a field.
  defp suggestions(form, field) do
    for {^field, {_message, opts}} <- form.errors, suggestion = opts[:suggestion], do: suggestion
  end

  @impl true
  def mount(params, _session, socket) do
    socket
    |> assign(:return_to, return_to(params["return_to"]))
    |> assign(:ingredient_search, nil)
    |> apply_action(socket.assigns.live_action, params)
    |> ok()
  end

  defp return_to("show"), do: "show"
  defp return_to(_), do: "index"

  defp apply_action(socket, :edit, _params) do
    %{current_scope: scope, recipe: recipe} = socket.assigns

    socket
    |> assign(:page_title, "Edit Recipe")
    |> assign_form(Recipes.change_recipe(scope, recipe))
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
  def handle_event("validate", %{"recipe" => recipe_params} = params, socket) do
    %{current_scope: scope, recipe: recipe} = socket.assigns
    changeset = Recipes.change_recipe(scope, recipe, recipe_params)

    socket
    |> assign_form(changeset, action: :validate)
    |> assign_ingredient_search(params)
    |> noreply()
  end

  def handle_event("save", %{"recipe" => recipe_params}, socket) do
    socket
    |> assign(:ingredient_search, nil)
    |> save_recipe(socket.assigns.live_action, recipe_params)
  end

  def handle_event("close_ingredient_search", _params, socket) do
    socket |> assign(:ingredient_search, nil) |> noreply()
  end

  # Searches the ingredients while typing an ingredient name. The search is
  # closed once the name matches an ingredient, or when typing elsewhere.
  defp assign_ingredient_search(
         socket,
         %{"_target" => ["recipe", "recipe_ingredients", index, "name"], "recipe" => params}
       ) do
    name = get_in(params, ["recipe_ingredients", index, "name"])
    results = Recipes.search_ingredients(socket.assigns.current_scope, name || "")

    search =
      with [_ | _] <- results,
           false <- Enum.any?(results, &(&1.name == Ingredient.normalize_name(name))),
           {index, ""} <- Integer.parse(index) do
        %{index: index, results: results}
      else
        _ -> nil
      end

    assign(socket, :ingredient_search, search)
  end

  defp assign_ingredient_search(socket, _params), do: assign(socket, :ingredient_search, nil)

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
    changeset =
      changeset
      |> Recipes.put_empty_last_recipe_step()
      |> Recipes.put_empty_last_recipe_ingredient()

    socket
    |> assign(:form, to_form(changeset, opts))
    |> assign(:ingredient_count, length(Recipes.ingredient_rows(changeset)))
  end

  defp return_path(_scope, "index", _recipe), do: ~p"/recipes"
  defp return_path(_scope, "show", recipe), do: ~p"/recipes/#{recipe}"
end
