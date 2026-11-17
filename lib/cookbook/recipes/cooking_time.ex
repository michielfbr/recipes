defmodule Cookbook.Recipes.CookingTime do
  @moduledoc """
  A cooking time, stored as a number of minutes and written as hours and
  minutes, like "1:30", "0:20" or "8:35".
  """

  use Ecto.Type

  @minutes ~r/^\d+$/
  @hours_minutes ~r/^(\d+):([0-5]\d)$/

  @impl true
  def type, do: :integer

  @doc """
  Casts "H:MM" strings and minutes, given as an integer or a string of
  digits. A blank string casts to `nil`.

  ## Examples

      iex> cast("1:30")
      {:ok, 90}

      iex> cast("90")
      {:ok, 90}

      iex> cast("")
      {:ok, nil}

      iex> cast("1:75")
      {:error, message: "must be minutes or hours:minutes, like 90 or 1:30"}

  """
  @impl true
  def cast(minutes) when is_integer(minutes) and minutes >= 0, do: {:ok, minutes}

  def cast(string) when is_binary(string) do
    string = String.trim(string)

    cond do
      string == "" ->
        {:ok, nil}

      string =~ @minutes ->
        {:ok, String.to_integer(string)}

      match = Regex.run(@hours_minutes, string, capture: :all_but_first) ->
        [hours, minutes] = match
        {:ok, String.to_integer(hours) * 60 + String.to_integer(minutes)}

      true ->
        {:error, message: "must be minutes or hours:minutes, like 90 or 1:30"}
    end
  end

  def cast(_), do: :error

  @impl true
  def load(minutes) when is_integer(minutes), do: {:ok, minutes}

  @impl true
  def dump(minutes) when is_integer(minutes), do: {:ok, minutes}
  def dump(_), do: :error

  @doc """
  Formats minutes as "H:MM". Anything else, like an invalid value typed in a
  form, is returned as is.

  ## Examples

      iex> format(90)
      "1:30"

      iex> format(20)
      "0:20"

      iex> format(nil)
      nil

  """
  def format(minutes) when is_integer(minutes) do
    "#{div(minutes, 60)}:#{minutes |> rem(60) |> Integer.to_string() |> String.pad_leading(2, "0")}"
  end

  def format(other), do: other
end
