defmodule CookbookWeb.LayoutsTest do
  use CookbookWeb.ConnCase

  describe "top bar" do
    setup :register_and_log_in_user

    test "has a Home link to the recipes listing", %{conn: conn} do
      document = conn |> get(~p"/recipes") |> html_response(200) |> LazyHTML.from_document()

      assert [_] = document |> LazyHTML.query("a#home-link[href='/recipes']") |> Enum.to_list()
    end

    test "has exactly one theme toggle, in the top bar", %{conn: conn} do
      document = conn |> get(~p"/recipes") |> html_response(200) |> LazyHTML.from_document()

      assert [_] = document |> LazyHTML.query("nav #theme-toggle") |> Enum.to_list()
      assert [_, _, _] = document |> LazyHTML.query("[data-phx-theme]") |> Enum.to_list()
    end

    test "has no Phoenix navbar", %{conn: conn} do
      document = conn |> get(~p"/recipes") |> html_response(200) |> LazyHTML.from_document()

      assert [] = document |> LazyHTML.query("header.navbar") |> Enum.to_list()

      assert [] =
               document
               |> LazyHTML.query("a[href='https://hexdocs.pm/phoenix/overview.html']")
               |> Enum.to_list()
    end
  end

  describe "top bar when logged out" do
    test "has no theme toggle", %{conn: conn} do
      document = conn |> get(~p"/users/log-in") |> html_response(200) |> LazyHTML.from_document()

      assert [] = document |> LazyHTML.query("#theme-toggle") |> Enum.to_list()
    end
  end
end
