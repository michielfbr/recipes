defmodule CookbookWeb.RecipeLive.Form do
  use CookbookWeb, :live_view

  alias Cookbook.Recipes
  alias Cookbook.Recipes.CookingTime
  alias Cookbook.Recipes.Import
  alias Cookbook.Recipes.Import.URL
  alias Cookbook.Recipes.Ingredient

  require Logger

  on_mount CookbookWeb.RecipeLive.LoadRecipe

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@page_title}
        <:subtitle :if={@import_form}>
          Paste a recipe from a website, email or note. It's translated to Dutch, and you can check it before saving.
        </:subtitle>
        <:subtitle :if={@import_host}>
          The recipe is read from the page and translated to Dutch. You can check it before saving.
        </:subtitle>
        <:subtitle :if={!@import_form and !@import_host}>
          Use this form to manage recipe records in your database.
        </:subtitle>
      </.header>

      <.import_text :if={@import_form} form={@import_form} reading?={@reading?} error={@import_error} />
      <.import_url :if={@import_host} host={@import_host} reading?={@reading?} error={@import_error} />

      <.form
        :if={!@import_form and !@import_host}
        for={@form}
        id="recipe-form"
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:title]} type="text" label="Title" />
        <div class="w-36">
          <.input
            field={@form[:cooking_time]}
            value={CookingTime.format(@form[:cooking_time].value)}
            type="text"
            label="Cooking time"
            placeholder="1:30"
            inputmode="numeric"
            phx-debounce="blur"
          />
        </div>
        <section id="recipe-ingredients" phx-hook=".IngredientRows" class="mt-2 mb-4">
          <h2 class="label mb-1 text-xs">Ingredients</h2>
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
        <footer class="flex items-center gap-2">
          <.button phx-disable-with="Saving..." variant="primary">Save Recipe</.button>
          <.button navigate={return_path(@current_scope, @return_to, @recipe)}>Cancel</.button>
          <button
            :if={@live_action == :edit}
            type="button"
            id="delete-recipe"
            phx-click="confirm_delete"
            class="btn btn-ghost ml-auto text-error transition-colors hover:bg-error/10"
          >
            <.icon name="hero-trash" class="size-4" /> Delete
          </button>
        </footer>
      </.form>

      <div
        :if={@confirm_delete?}
        id="confirm-delete-modal"
        role="alertdialog"
        aria-modal="true"
        aria-labelledby="confirm-delete-title"
        class="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4 backdrop-blur-sm transition-opacity duration-150 starting:opacity-0"
        phx-window-keydown="cancel_delete"
        phx-key="Escape"
      >
        <div
          class="w-full max-w-sm rounded-box bg-base-100 p-6 shadow-xl transition duration-150 starting:scale-95 starting:opacity-0"
          phx-click-away="cancel_delete"
        >
          <div class="flex items-start gap-4">
            <div class="flex size-10 shrink-0 items-center justify-center rounded-full bg-error/10">
              <.icon name="hero-exclamation-triangle" class="size-5 text-error" />
            </div>
            <div>
              <h2 id="confirm-delete-title" class="text-base font-semibold">{@recipe.title}</h2>
              <p class="mt-1 text-sm text-base-content/70">
                This recipe will be permanently deleted. Are you sure?
              </p>
            </div>
          </div>
          <div class="mt-6 flex justify-end gap-2">
            <button
              type="button"
              id="cancel-delete"
              phx-click="cancel_delete"
              class="btn btn-ghost"
            >
              Cancel
            </button>
            <button
              type="button"
              id="confirm-delete"
              phx-click="delete"
              phx-disable-with="Deleting..."
              class="btn btn-error"
            >
              Delete
            </button>
          </div>
        </div>
      </div>
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

  attr :form, Phoenix.HTML.Form, required: true
  attr :reading?, :boolean, required: true
  attr :error, :string, default: nil

  defp import_text(assigns) do
    ~H"""
    <.form for={@form} id="import-text-form" phx-change="import_change" phx-submit="import">
      <.input
        field={@form[:text]}
        type="textarea"
        label="Recipe text"
        rows="8"
        required
        readonly={@reading?}
        placeholder="Paste the recipe here: the title, ingredients and steps"
        phx-debounce="200"
        class={[
          "w-full textarea sm:min-h-80 font-mono text-sm leading-relaxed transition",
          @reading? && "opacity-60"
        ]}
      />

      <div
        :if={@error}
        id="import-error"
        role="alert"
        class="mb-4 flex flex-col gap-3 rounded-xl border border-error/30 bg-error/5 p-4 sm:flex-row sm:items-center"
      >
        <p class="flex flex-1 items-center gap-2 text-sm">
          <.icon name="hero-exclamation-triangle" class="size-5 shrink-0 text-error" />
          {@error}
        </p>
        <.button id="import-start-from-scratch" navigate={~p"/recipes/new"} class="btn btn-sm">
          Start from scratch
        </.button>
      </div>

      <.import_reading :if={@reading?}>Reading recipe…</.import_reading>

      <footer class="flex items-center gap-2">
        <.button
          id="import-submit"
          variant="primary"
          disabled={@reading? or blank?(@form[:text].value)}
        >
          <%= if @reading? do %>
            <.icon name="hero-arrow-path" class="size-4 animate-spin" /> Reading…
          <% else %>
            <.icon name="hero-sparkles" class="size-4" /> Read recipe
          <% end %>
        </.button>
        <.button navigate={~p"/recipes"}>Cancel</.button>
      </footer>
    </.form>
    """
  end

  attr :host, :string, required: true
  attr :reading?, :boolean, required: true
  attr :error, :string, default: nil

  defp import_url(assigns) do
    ~H"""
    <div id="import-url">
      <.import_reading :if={@reading?}>Reading recipe from {@host}…</.import_reading>

      <div
        :if={@error}
        id="import-error"
        role="alert"
        class="mb-4 rounded-xl border border-error/30 bg-error/5 p-4 transition duration-200 starting:opacity-0"
      >
        <p class="flex items-start gap-2 text-sm">
          <.icon name="hero-exclamation-triangle" class="mt-0.5 size-5 shrink-0 text-error" />
          <span>
            {@error}
            <span class="mt-0.5 block text-base-content/60">{@host}</span>
          </span>
        </p>
        <div class="mt-4 flex flex-col gap-2 sm:flex-row">
          <.button id="import-paste-text" variant="primary" navigate={~p"/recipes/import"}>
            <.icon name="hero-clipboard-document-list" class="size-4" /> Paste text instead
          </.button>
          <.button id="import-start-from-scratch" navigate={~p"/recipes/new"}>
            Start from scratch
          </.button>
        </div>
      </div>

      <footer :if={@reading?} class="flex items-center gap-2">
        <.button navigate={~p"/recipes"}>Cancel</.button>
      </footer>
    </div>
    """
  end

  slot :inner_block, required: true

  defp import_reading(assigns) do
    ~H"""
    <div id="import-reading" aria-live="polite" class="mb-4 rounded-xl border border-base-300 p-4">
      <p class="mb-3 flex items-center gap-2 text-sm font-medium">
        <.icon name="hero-sparkles" class="size-5 shrink-0 animate-pulse text-primary" />
        <span class="min-w-0 truncate">{render_slot(@inner_block)}</span>
      </p>
      <div class="space-y-2 animate-pulse" aria-hidden="true">
        <div class="h-4 w-1/2 rounded bg-base-300"></div>
        <div class="h-3 w-1/3 rounded bg-base-200"></div>
        <div class="h-3 w-2/5 rounded bg-base-200"></div>
        <div class="h-3 w-5/6 rounded bg-base-200"></div>
        <div class="h-3 w-3/4 rounded bg-base-200"></div>
      </div>
    </div>
    """
  end

  defp blank?(value), do: value in [nil, ""] or String.trim(value) == ""

  # The values suggested by "did you mean" errors on a field.
  defp suggestions(form, field) do
    for {^field, {_message, opts}} <- form.errors, suggestion = opts[:suggestion], do: suggestion
  end

  @impl true
  def mount(params, _session, socket) do
    socket
    |> assign(:return_to, return_to(params["return_to"]))
    |> assign(:ingredient_search, nil)
    |> assign(:confirm_delete?, false)
    |> assign(:import_form, nil)
    |> assign(:import_host, nil)
    |> assign(:reading?, false)
    |> assign(:import_error, nil)
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

  # Reads the recipe from the page at `url` right away. Once it's read, the
  # recipe form is shown filled in, and saving works as for a new recipe.
  defp apply_action(socket, :import, %{"url" => url} = params) do
    scope = socket.assigns.current_scope
    socket = socket |> apply_action(:new, params) |> assign(:page_title, "Import Recipe")

    case URL.clean(url) do
      {:ok, clean_url} ->
        socket
        |> assign(:import_host, URI.parse(clean_url).host)
        |> assign(:reading?, true)
        |> start_async(:import, fn -> Import.from_url(scope, clean_url) end)

      {:error, reason} ->
        socket
        |> assign(:import_host, String.trim(url))
        |> import_failed(reason)
    end
  end

  # Asks for the text to import first. Once it's read, the recipe form is shown
  # filled in, and saving works as for a new recipe.
  defp apply_action(socket, :import, params) do
    socket
    |> apply_action(:new, params)
    |> assign(:page_title, "Import Recipe")
    |> assign(:import_form, to_form(%{"text" => ""}, as: :import))
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

  def handle_event("import_change", %{"import" => import_params}, socket) do
    socket |> assign(:import_form, to_form(import_params, as: :import)) |> noreply()
  end

  def handle_event("import", %{"import" => %{"text" => text} = import_params}, socket) do
    scope = socket.assigns.current_scope

    socket
    |> assign(:import_form, to_form(import_params, as: :import))
    |> assign(:reading?, true)
    |> assign(:import_error, nil)
    |> start_async(:import, fn -> Import.from_text(scope, text) end)
    |> noreply()
  end

  def handle_event("save", %{"recipe" => recipe_params}, socket) do
    socket
    |> assign(:ingredient_search, nil)
    |> save_recipe(socket.assigns.live_action, recipe_params)
  end

  def handle_event("confirm_delete", _params, %{assigns: %{live_action: :edit}} = socket) do
    socket |> assign(:confirm_delete?, true) |> noreply()
  end

  def handle_event("cancel_delete", _params, socket) do
    socket |> assign(:confirm_delete?, false) |> noreply()
  end

  def handle_event("delete", _params, %{assigns: %{live_action: :edit}} = socket) do
    {:ok, _} = Recipes.delete_recipe(socket.assigns.current_scope, socket.assigns.recipe)

    socket
    |> put_flash(:info, "Recipe deleted successfully")
    |> push_navigate(to: ~p"/recipes")
    |> noreply()
  end

  def handle_event("close_ingredient_search", _params, socket) do
    socket |> assign(:ingredient_search, nil) |> noreply()
  end

  @impl true
  def handle_async(:import, {:ok, {:ok, recipe_params}}, socket) do
    %{current_scope: scope, recipe: recipe} = socket.assigns

    socket
    |> assign(:reading?, false)
    |> assign(:import_form, nil)
    |> assign(:import_host, nil)
    |> assign_form(Recipes.change_recipe(scope, recipe, recipe_params), action: :validate)
    |> put_flash(:info, "Imported, check everything before saving")
    |> noreply()
  end

  def handle_async(:import, {:ok, {:error, reason}}, socket) do
    socket |> import_failed(reason) |> noreply()
  end

  def handle_async(:import, {:exit, reason}, socket) do
    Logger.error("Recipe import crashed: #{inspect(reason)}")
    socket |> import_failed(:ai_failed) |> noreply()
  end

  defp import_failed(socket, reason) do
    source = if socket.assigns.import_host, do: :url, else: :text

    socket
    |> assign(:reading?, false)
    |> assign(:import_error, import_error_message(reason, source))
  end

  defp import_error_message(:empty, _source), do: "Paste a recipe first."
  defp import_error_message(:no_recipe, :text), do: "No recipe found in this text."
  defp import_error_message(:no_recipe, :url), do: "No recipe found on this page."
  defp import_error_message(:invalid_url, _source), do: "That doesn't look like a web address."

  defp import_error_message(:blocked, _source),
    do: "This site doesn't allow importing. Copy the recipe text and use 'From text'."

  defp import_error_message(reason, _source) when reason in [:unreachable, :not_found],
    do: "Couldn't open this page."

  defp import_error_message(reason, _source) when reason in [:too_large, :not_html],
    do: "This page can't be imported."

  defp import_error_message(reason, _source) when reason in [:ai_unavailable, :ai_failed],
    do: "Reading the recipe failed, try again."

  defp import_error_message(:no_credits, _source), do: "Importing isn't available right now."

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

  defp save_recipe(socket, action, recipe_params) when action in [:new, :import] do
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
