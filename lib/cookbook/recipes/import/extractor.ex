defmodule Cookbook.Recipes.Import.Extractor do
  @moduledoc """
  Finds the recipe in a web page and reduces it to a small piece of content
  for the AI, so it doesn't have to read the whole page.

  It tries these steps in order and stops at the first that finds a recipe:

    1. `:json_ld` - a schema.org `Recipe` in a JSON-LD script, reduced to the
       fields the recipe form needs.
    2. `:microdata` - the text of `itemprop="recipeIngredient"` and similar
       elements.
    3. `:text` - the readable text of the page, without navigation, scripts
       and the like. When that text is too short to hold the steps (as on
       pages built with Next.js), prose found in the page's inline scripts is
       added to it.
  """

  @json_ld_fields ~w(name recipeIngredient recipeInstructions totalTime cookTime prepTime recipeYield)
  @microdata_props ~w(name recipeIngredient ingredients recipeInstructions totalTime cookTime prepTime recipeYield)

  @removed_tags ~w(script style noscript svg iframe nav header footer aside form template)
  @block_tags ~w(address article blockquote br dd details div dl dt figcaption figure h1 h2 h3
                 h4 h5 h6 hr li main ol p pre section summary table tbody td tfoot th thead tr ul)

  @min_length 200
  @short_text_length 2_000

  # A JavaScript string literal (possessive, so huge literals don't backtrack).
  @string_literal ~r/"((?:[^"\\]++|\\.)*+)"/s
  @code_chars ~r/[{}<>=;\\|`$\[\]]/
  @url ~r/https?:|www\./i

  @type content :: {:json_ld, map()} | {:microdata | :text, String.t()}

  @doc """
  Extracts the recipe from the HTML of a page.

  Returns `{:error, :no_recipe}` when no step finds anything that could be a
  recipe.
  """
  @spec extract(String.t()) :: {:ok, content()} | {:error, :no_recipe}
  def extract(html) when is_binary(html) do
    doc = LazyHTML.from_document(html)

    case json_ld(doc) || microdata(doc) || text(doc) do
      {:json_ld, _recipe} = content -> {:ok, content}
      {_kind, text} = content when byte_size(text) >= @min_length -> {:ok, content}
      _too_short -> {:error, :no_recipe}
    end
  end

  ## JSON-LD

  defp json_ld(doc) do
    doc
    |> LazyHTML.query(~s{script[type="application/ld+json"]})
    |> Enum.find_value(fn script ->
      case Jason.decode(LazyHTML.text(script)) do
        {:ok, data} -> find_recipe(data)
        {:error, _} -> nil
      end
    end)
    |> case do
      nil -> nil
      recipe -> {:json_ld, reduce_recipe(recipe)}
    end
  end

  defp find_recipe(list) when is_list(list), do: Enum.find_value(list, &find_recipe/1)

  defp find_recipe(%{} = data) do
    if recipe_type?(data["@type"]) and
         (data["recipeIngredient"] || data["recipeInstructions"]) not in [nil, []] do
      data
    else
      find_recipe(data["@graph"]) || find_recipe(data["mainEntity"])
    end
  end

  defp find_recipe(_other), do: nil

  defp recipe_type?(types) when is_list(types), do: Enum.any?(types, &recipe_type?/1)

  defp recipe_type?(type) when is_binary(type),
    do: type == "Recipe" or String.ends_with?(type, ["/Recipe", ":Recipe"])

  defp recipe_type?(_type), do: false

  defp reduce_recipe(recipe) do
    recipe
    |> Map.take(@json_ld_fields)
    |> Map.update("recipeInstructions", [], &instruction_texts/1)
    |> Map.reject(fn {_field, value} -> value in [nil, "", []] end)
  end

  # Instructions can be a string, HowToStep objects, or HowToSection objects
  # with steps inside. Keep only their text.
  defp instruction_texts(list) when is_list(list), do: Enum.flat_map(list, &instruction_texts/1)
  defp instruction_texts(text) when is_binary(text), do: [text]

  defp instruction_texts(%{"itemListElement" => steps} = section) do
    case section["name"] do
      name when is_binary(name) and name != "" -> [name <> ":" | instruction_texts(steps)]
      _ -> instruction_texts(steps)
    end
  end

  defp instruction_texts(%{"text" => text}) when is_binary(text), do: [text]
  defp instruction_texts(%{"name" => name}) when is_binary(name), do: [name]
  defp instruction_texts(_other), do: []

  ## Microdata

  defp microdata(doc) do
    selector = Enum.map_join(@microdata_props, ", ", &~s([itemprop="#{&1}"]))

    lines =
      doc
      |> LazyHTML.query(selector)
      |> Enum.map(fn element ->
        [prop] = LazyHTML.attribute(element, "itemprop")

        value =
          attribute(element, "content") || attribute(element, "datetime") ||
            element |> LazyHTML.text() |> String.replace(~r/\s+/u, " ") |> String.trim()

        {prop, value}
      end)
      |> Enum.reject(fn {_prop, value} -> value == "" end)
      |> Enum.uniq()

    if Enum.any?(lines, fn {prop, _} -> prop in ["recipeIngredient", "ingredients"] end) do
      {:microdata, Enum.map_join(lines, "\n", fn {prop, value} -> "#{prop}: #{value}" end)}
    end
  end

  defp attribute(element, name) do
    case LazyHTML.attribute(element, name) do
      [value | _] when value != "" -> value
      _ -> nil
    end
  end

  ## Page text

  defp text(doc) do
    text = text_of(main_content(doc))

    if String.length(text) < @short_text_length do
      prose = Enum.reject(script_prose(doc), &String.contains?(text, &1))
      {:text, Enum.join([text | prose], "\n") |> String.trim()}
    else
      {:text, text}
    end
  end

  defp main_content(doc) do
    Enum.find_value(["main", "article", "body"], doc, fn selector ->
      case Enum.take(LazyHTML.query(doc, selector), 1) do
        [element] -> element
        [] -> nil
      end
    end)
  end

  defp text_of(element) do
    element
    |> LazyHTML.to_tree()
    |> node_text()
    |> IO.iodata_to_binary()
    |> collapse_whitespace()
  end

  defp node_text(nodes) when is_list(nodes), do: Enum.map(nodes, &node_text/1)
  # Line breaks in the HTML source are just spaces; block elements make lines.
  defp node_text(text) when is_binary(text), do: String.replace(text, ~r/\s+/u, " ")
  defp node_text({tag, _attrs, _children}) when tag in @removed_tags, do: []
  defp node_text({"li", _attrs, children}), do: ["\n- ", node_text(children), "\n"]

  defp node_text({tag, _attrs, children}) when tag in @block_tags,
    do: ["\n", node_text(children), "\n"]

  defp node_text({_tag, _attrs, children}), do: node_text(children)
  defp node_text(_comment), do: []

  defp collapse_whitespace(text) do
    text
    |> String.split("\n")
    |> Enum.map(&(&1 |> String.replace(~r/\s+/u, " ") |> String.trim()))
    |> Enum.reject(&(&1 == ""))
    |> join_list_markers()
    |> Enum.join("\n")
  end

  # A list item whose text sits in a block element ends up as "-" on its own line.
  defp join_list_markers(["-", line | rest]), do: join_list_markers(["- " <> line | rest])
  defp join_list_markers([line | rest]), do: [line | join_list_markers(rest)]
  defp join_list_markers([]), do: []

  ## Prose in inline scripts

  defp script_prose(doc) do
    doc
    |> LazyHTML.query(~s{script:not([src]):not([type="application/ld+json"])})
    |> Enum.flat_map(&(&1 |> LazyHTML.text() |> prose_literals(2)))
    |> Enum.uniq()
  end

  # Finds prose in string literals. Literals can hold escaped JSON or
  # JavaScript with more literals inside, so look inside them up to `depth`
  # times.
  defp prose_literals(source, depth) do
    for [literal] <- Regex.scan(@string_literal, source, capture: :all_but_first),
        string <- [unescape(literal)],
        found <- prose_in(string, depth),
        do: found
  end

  defp prose_in(string, depth) do
    cond do
      prose?(string) -> [string]
      depth > 0 and String.contains?(string, "\"") -> prose_literals(string, depth - 1)
      true -> []
    end
  end

  # Also drops markdown bold, so a step that appears with and without it is
  # only kept once.
  defp unescape(literal) do
    case Jason.decode(~s("#{literal}")) do
      {:ok, string} -> String.replace(string, "**", "")
      {:error, _} -> literal
    end
  end

  defp prose?(string) do
    length = String.length(string)
    words = String.split(string, " ", trim: true)

    length >= 40 and
      length(words) > 6 and
      letters_and_spaces(string) / length > 0.85 and
      not Regex.match?(@code_chars, string) and
      not Regex.match?(@url, string) and
      not css_classes?(words)
  end

  # Class lists like "flex w-full flex-col justify-center gap-8".
  defp css_classes?(words) do
    Enum.count(words, &String.contains?(&1, ["-", ":"])) * 4 > length(words)
  end

  defp letters_and_spaces(string) do
    ~r/[\p{L}\s]/u |> Regex.scan(string) |> length()
  end
end
