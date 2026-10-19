defmodule Cookbook.Recipes.AmountTest do
  use ExUnit.Case, async: true

  alias Cookbook.Recipes.Amount

  doctest Amount

  describe "parse/1" do
    for {amount, quantity, unit} <- [
          {"250g", "250", "g"},
          {"250 g", "250", "g"},
          {" 250  Gram ", "250", "g"},
          {"250 gr.", "250", "g"},
          {"1,5 kg", "1.5", "kg"},
          {"1.5 kilo", "1.5", "kg"},
          {"1/2 cup", "0.5", "kop"},
          {"1 1/2 tbsp", "1.5", "el"},
          {"½ theelepel", "0.5", "tl"},
          {"1½ el", "1.5", "el"},
          {"1/3 l", "0.333", "l"},
          {"3", "3", nil},
          {"snufje", nil, "snufje"},
          {"2 large eggs", "2", "large eggs"},
          {"", nil, nil}
        ] do
      test "reads #{inspect(amount)}" do
        assert {:ok, {quantity, unit}} = Amount.parse(unquote(amount))
        assert unit == unquote(unit)
        assert_quantity(quantity, unquote(quantity))
      end
    end

    test "suggests the total amount for multiplied amounts" do
      assert {:error, {_, suggestion: "400 g"}} = Amount.parse("1 x 400g can")
      assert {:error, {_, suggestion: "800 g"}} = Amount.parse("2x400 gram")
      assert {:error, {_, suggestion: "1 l"}} = Amount.parse("2 × 1/2 l")
    end

    for amount <- ["±200 g", "2-3 cloves", "1 2", "400g + 200g"] do
      test "can't read #{inspect(amount)}" do
        assert {:error, {"can't read this amount", []}} = Amount.parse(unquote(amount))
      end
    end

    test "rejects zero" do
      assert {:error, {"must be more than 0", []}} = Amount.parse("0 g")
      assert {:error, {"can't divide by 0", []}} = Amount.parse("1/0 g")
    end
  end

  describe "format/2" do
    test "formats whole numbers, fractions and decimals" do
      assert Amount.format(Decimal.new("250.000"), "g") == "250 g"
      assert Amount.format(Decimal.new("0.5"), "tl") == "½ tl"
      assert Amount.format(Decimal.new("0.333"), "l") == "⅓ l"
      assert Amount.format(Decimal.new("2.2"), nil) == "2,2"
      assert Amount.format(nil, "snufje") == "snufje"
      assert Amount.format(nil, nil) == ""
    end

    test "is read back by parse/1" do
      for amount <- ["250 g", "1½ el", "⅔ kop", "1,2 kg", "1¼ kg", "3"] do
        {:ok, {quantity, unit}} = Amount.parse(amount)
        assert Amount.format(quantity, unit) == amount
      end
    end
  end

  defp assert_quantity(nil, expected), do: assert(expected == nil)
  defp assert_quantity(quantity, expected), do: assert(Decimal.equal?(quantity, expected))
end
