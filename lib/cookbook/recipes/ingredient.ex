defmodule Cookbook.Recipes.Ingredient do
  @moduledoc """
  An ingredient, shared by all users. Names are stored normalized (see
  `normalize_name/1`), so "Tomato" and " tomato " are the same ingredient.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "ingredients" do
    field :name, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(ingredient, attrs) do
    ingredient
    |> cast(attrs, [:name])
    |> update_change(:name, &normalize_name/1)
    |> validate_required([:name])
    |> unique_constraint(:name)
  end

  @doc """
  Trims, collapses whitespace and lowercases an ingredient name.

  ## Examples

      iex> Cookbook.Recipes.Ingredient.normalize_name("  Red   Onion ")
      "red onion"

  """
  def normalize_name(nil), do: nil

  def normalize_name(name) do
    name |> String.trim() |> String.replace(~r/\s+/u, " ") |> String.downcase()
  end
end
