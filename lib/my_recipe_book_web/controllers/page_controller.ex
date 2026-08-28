defmodule MyRecipeBookWeb.PageController do
  use MyRecipeBookWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
