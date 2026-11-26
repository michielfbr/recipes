defmodule Cookbook.Recipes.Import.ExtractorTest do
  use ExUnit.Case, async: true

  alias Cookbook.Recipes.Import.Extractor

  @fixtures "test/support/fixtures/recipe_pages"

  defp fixture(name), do: File.read!(Path.join(@fixtures, name))

  defp page(body),
    do: "<!doctype html><html><head><title>Test</title></head><body>#{body}</body></html>"

  defp json_ld(data) do
    ~s(<script type="application/ld+json">#{Jason.encode!(data)}</script>)
  end

  describe "extract/1 with JSON-LD" do
    test "De Krat gives the recipe fields without images or authors" do
      assert {:ok, {:json_ld, recipe}} = Extractor.extract(fixture("dekrat.html"))

      assert recipe["name"] == "Groentepaella met sperziebonen en zeekraal"
      assert length(recipe["recipeIngredient"]) == 14
      assert Enum.all?(recipe["recipeInstructions"], &is_binary/1)
      assert hd(recipe["recipeInstructions"]) =~ "Snipper de ui."
      refute Map.has_key?(recipe, "image")
      refute Map.has_key?(recipe, "author")
      refute Map.has_key?(recipe, "cookTime")
    end

    test "finds a recipe inside @graph with a list as @type" do
      html =
        page(
          json_ld(%{
            "@context" => "https://schema.org",
            "@graph" => [
              %{"@type" => "WebPage", "name" => "Page"},
              %{
                "@type" => ["Recipe", "NewsArticle"],
                "name" => "Soep",
                "recipeIngredient" => ["1 ui"],
                "recipeInstructions" => "Kook de ui.",
                "totalTime" => "PT30M"
              }
            ]
          })
        )

      assert Extractor.extract(html) ==
               {:ok,
                {:json_ld,
                 %{
                   "name" => "Soep",
                   "recipeIngredient" => ["1 ui"],
                   "recipeInstructions" => ["Kook de ui."],
                   "totalTime" => "PT30M"
                 }}}
    end

    test "flattens HowToSection and HowToStep instructions to text" do
      html =
        page(
          json_ld(%{
            "@type" => "Recipe",
            "name" => "Taart",
            "recipeIngredient" => ["bloem"],
            "recipeInstructions" => [
              %{
                "@type" => "HowToSection",
                "name" => "Deeg",
                "itemListElement" => [
                  %{"@type" => "HowToStep", "text" => "Kneed.", "image" => "x.jpg"}
                ]
              },
              "Bak."
            ]
          })
        )

      assert {:ok, {:json_ld, recipe}} = Extractor.extract(html)
      assert recipe["recipeInstructions"] == ["Deeg:", "Kneed.", "Bak."]
    end

    test "Boerschappen gives its non-standard steps and yield fields as the standard ones" do
      assert {:ok, {:json_ld, recipe}} = Extractor.extract(fixture("boerschappen.html"))

      assert recipe["name"] == "Okonomiyaki met gerookte zalm"
      assert length(recipe["recipeIngredient"]) == 12
      assert hd(recipe["recipeInstructions"]) =~ "Snijd de prei in dunne ringen"
      assert Enum.all?(recipe["recipeInstructions"], &is_binary/1)
      assert recipe["recipeYield"] == 2
      refute Map.has_key?(recipe, "steps")
    end

    test "falls back to the page text when the JSON-LD recipe has no steps" do
      steps =
        Enum.map_join(
          1..4,
          "",
          &"<li>Stap #{&1}: bak de pannenkoek #{&1} minuten op middelhoog vuur.</li>"
        )

      html =
        page("""
        #{json_ld(%{"@type" => "Recipe", "name" => "Pannenkoeken", "recipeIngredient" => ["250 g bloem"]})}
        <main><h1>Pannenkoeken</h1><ol>#{steps}</ol></main>
        """)

      assert {:ok, {:text, text}} = Extractor.extract(html)
      assert text =~ "- Stap 4: bak de pannenkoek"
    end

    test "skips invalid JSON-LD" do
      html = page(~s(<script type="application/ld+json">{not json</script><nav>Menu</nav>))
      assert Extractor.extract(html) == {:error, :no_recipe}
    end
  end

  describe "extract/1 with microdata" do
    test "returns the itemprop values as lines" do
      ingredients =
        Enum.map_join(
          1..8,
          "",
          &~s(<li itemprop="recipeIngredient">#{&1}00 g ingrediënt #{&1}</li>)
        )

      html =
        page("""
        <div itemscope itemtype="https://schema.org/Recipe">
          <h1 itemprop="name">Stamppot</h1>
          <meta itemprop="totalTime" content="PT45M">
          <ul>#{ingredients}</ul>
          <p itemprop="recipeInstructions">Kook de aardappels en stamp ze fijn.</p>
        </div>
        """)

      assert {:ok, {:microdata, text}} = Extractor.extract(html)
      assert text =~ "name: Stamppot"
      assert text =~ "totalTime: PT45M"
      assert text =~ "recipeIngredient: 300 g ingrediënt 3"
      assert text =~ "recipeInstructions: Kook de aardappels en stamp ze fijn."
    end
  end

  describe "extract/1 with page text" do
    test "Picnic gives the ingredients from the page and the steps from its scripts" do
      assert {:ok, {:text, text}} = Extractor.extract(fixture("picnic.html"))

      assert text =~ "chorizoworst"
      assert text =~ "Kook ondertussen 300 g fusilli"
      refute text =~ "**"
      refute text =~ "justify-center"
      assert length(String.split(text, "Kook ondertussen 300 g fusilli")) == 2
    end

    test "uses <main>, drops navigation and marks list items" do
      steps =
        Enum.map_join(1..5, "", &"<li>Stap #{&1}: roer het geheel #{&1} minuten goed door.</li>")

      html =
        page("""
        <header>Logo</header>
        <nav><a href="/">Home</a></nav>
        <p>Buiten main</p>
        <main>
          <h1>Erwtensoep</h1>
          <script>var x = 1;</script>
          <ul>#{steps}</ul>
          <p>Serveer   met
             roggebrood en spek.</p>
        </main>
        <footer>Contact</footer>
        """)

      assert {:ok, {:text, text}} = Extractor.extract(html)

      assert text ==
               """
               Erwtensoep
               - Stap 1: roer het geheel 1 minuten goed door.
               - Stap 2: roer het geheel 2 minuten goed door.
               - Stap 3: roer het geheel 3 minuten goed door.
               - Stap 4: roer het geheel 4 minuten goed door.
               - Stap 5: roer het geheel 5 minuten goed door.
               Serveer met roggebrood en spek.\
               """
    end

    test "a page with only navigation gives :no_recipe" do
      html =
        page("""
        <header><a href="/">Home</a></header>
        <nav><ul><li><a href="/recepten">Recepten</a></li><li><a href="/over">Over ons</a></li></ul></nav>
        <main><h1>Welkom</h1></main>
        <footer>© 2026</footer>
        """)

      assert Extractor.extract(html) == {:error, :no_recipe}
    end
  end
end
