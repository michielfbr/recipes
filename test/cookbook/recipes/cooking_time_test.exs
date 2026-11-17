defmodule Cookbook.Recipes.CookingTimeTest do
  use ExUnit.Case, async: true

  alias Cookbook.Recipes.CookingTime

  import CookingTime, only: [cast: 1, format: 1]
  doctest CookingTime

  test "cast/1 reads hours and minutes" do
    assert cast("0:20") == {:ok, 20}
    assert cast("8:35") == {:ok, 515}
    assert cast(" 1:30 ") == {:ok, 90}
    assert cast(45) == {:ok, 45}
  end

  test "cast/1 reads a number as minutes" do
    assert cast("90") == {:ok, 90}
    assert cast("515") == {:ok, 515}
    assert cast("0") == {:ok, 0}
  end

  test "cast/1 rejects anything else" do
    for invalid <- ["1:5", "1.5", "-90", "1:60", "1h30", "-1:00", ":30"] do
      assert {:error, _} = cast(invalid), "expected #{inspect(invalid)} to be invalid"
    end

    assert cast(-5) == :error
  end

  test "format/1 writes hours and minutes" do
    assert format(0) == "0:00"
    assert format(515) == "8:35"
    assert format(600) == "10:00"
    assert format("1:5") == "1:5"
  end
end
