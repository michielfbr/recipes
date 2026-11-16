defmodule CookbookWeb.LayoutsTest do
  use CookbookWeb.ConnCase

  describe "top bar" do
    setup :register_and_log_in_user

    test "has a Home link to the recipes listing", %{conn: conn} do
      document = conn |> get(~p"/recipes") |> html_response(200) |> LazyHTML.from_document()

      assert [_] = document |> LazyHTML.query("a#home-link[href='/recipes']") |> Enum.to_list()
    end
  end
end
