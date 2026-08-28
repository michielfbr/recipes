defmodule MyRecipeBook.Repo do
  use Ecto.Repo,
    otp_app: :my_recipe_book,
    adapter: Ecto.Adapters.Postgres
end
