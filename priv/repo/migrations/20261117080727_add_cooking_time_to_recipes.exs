defmodule Cookbook.Repo.Migrations.AddCookingTimeToRecipes do
  use Ecto.Migration

  def change do
    alter table(:recipes) do
      # in minutes
      add :cooking_time, :integer
    end
  end
end
