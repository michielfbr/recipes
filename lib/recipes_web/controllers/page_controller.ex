defmodule RecipesWeb.PageController do
  use RecipesWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
