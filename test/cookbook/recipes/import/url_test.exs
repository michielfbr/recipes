defmodule Cookbook.Recipes.Import.URLTest do
  use ExUnit.Case, async: true

  alias Cookbook.Recipes.Import.URL

  doctest URL, import: true

  describe "clean/1" do
    test "removes utm_ parameters and the ? when nothing is left" do
      assert URL.clean("https://example.com/recept?utm_source=nieuwsbrief&utm_medium=email") ==
               {:ok, "https://example.com/recept"}
    end

    test "keeps other parameters in their original order" do
      assert URL.clean("https://example.com/recept?id=5&utm_campaign=x&page=2") ==
               {:ok, "https://example.com/recept?id=5&page=2"}
    end

    test "leaves a URL without parameters unchanged" do
      assert URL.clean("https://www.dekrat.nl/recepten/pasta") ==
               {:ok, "https://www.dekrat.nl/recepten/pasta"}
    end

    test "keeps the path and fragment" do
      assert URL.clean("  http://example.com/a/b?utm_term=x#stap-2 \n") ==
               {:ok, "http://example.com/a/b#stap-2"}
    end

    test "only removes parameters whose name starts with utm_" do
      assert URL.clean("https://example.com/?my_utm_id=1&UTM_Source=x&q=utm_source") ==
               {:ok, "https://example.com/?my_utm_id=1&q=utm_source"}
    end

    test "rejects URLs that are not http or https with a host" do
      assert URL.clean("ftp://example.com") == {:error, :invalid_url}
      assert URL.clean("not a url") == {:error, :invalid_url}
      assert URL.clean("example.com/recept") == {:error, :invalid_url}
      assert URL.clean("https://") == {:error, :invalid_url}
      assert URL.clean("") == {:error, :invalid_url}
    end
  end
end
