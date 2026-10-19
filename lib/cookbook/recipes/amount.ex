defmodule Cookbook.Recipes.Amount do
  @moduledoc """
  Parses ingredient amounts like "250 g", "1,5 kg", "1 1/2 el" or "½ tl" into a
  decimal quantity and a unit, and formats them back.

  Unit spellings are normalized to Dutch short units, so "gr", "gram" and
  "grams" all become "g", and "eetlepel" and "tbsp" become "el". Units not
  listed are kept as typed (lowercased).
  """

  @units %{
    "g" => ~w(g gr gram grammen grams),
    "kg" => ~w(kg kilo kilos kilogram kilogrammen kilograms),
    "mg" => ~w(mg milligram milligrammen milligrams),
    "ml" => ~w(ml milliliter milliliters millilitre millilitres),
    "cl" => ~w(cl centiliter centiliters),
    "dl" => ~w(dl deciliter deciliters),
    "l" => ~w(l liter liters litre litres),
    "el" => ~w(el eetlepel eetlepels tbsp tbs tablespoon tablespoons),
    "tl" => ~w(tl theelepel theelepels tsp teaspoon teaspoons),
    "kl" => ~w(kl koffielepel koffielepels),
    "kop" => ~w(kop kopje kopjes koppen cup cups),
    "snufje" => ~w(snufje snufjes snuf pinch),
    "teen" => ~w(teen teentje teentjes tenen clove cloves),
    "blik" => ~w(blik blikje blikjes blikken can cans tin tins),
    "stuk" => ~w(stuk stuks stukje stukjes piece pieces),
    "bos" => ~w(bos bosje bosjes bunch),
    "plak" => ~w(plak plakje plakjes slice slices),
    "handje" => ~w(handje handjes handvol handful)
  }
  @unit_aliases for {unit, aliases} <- @units, alias <- aliases, into: %{}, do: {alias, unit}

  @fractions %{"½" => "1/2", "⅓" => "1/3", "⅔" => "2/3", "¼" => "1/4", "¾" => "3/4", "⅛" => "1/8"}
  @fraction_glyphs %{
    "0.5" => "½",
    "0.333" => "⅓",
    "0.667" => "⅔",
    "0.25" => "¼",
    "0.75" => "¾",
    "0.125" => "⅛"
  }

  # Mixed fraction ("1 1/2"), fraction ("1/2") or decimal ("1,5" or "1.5").
  @number ~S"\d+ \d+/\d+|\d+/\d+|\d+(?:[.,]\d+)?"
  @amount Regex.compile!("^(?<quantity>#{@number})? ?(?<unit>\\p{L}[\\p{L}. ]*)?$", "u")
  @multiplied Regex.compile!(
                "^(?<times>#{@number}) ?[x×*] ?(?<quantity>#{@number}) ?(?<unit>\\p{L}+\\.?)?",
                "u"
              )

  @scale 3

  @doc """
  Parses an amount into `{:ok, {quantity, unit}}`, where both may be `nil`.

  Returns `{:error, {message, opts}}` (ready for `Ecto.Changeset.add_error/4`)
  when it can't be read. For amounts like "1 x 400g can" the error suggests
  the total amount in its `:suggestion` option.

  ## Examples

      iex> Cookbook.Recipes.Amount.parse("1 1/2 Eetlepel")
      {:ok, {Decimal.new("1.500"), "el"}}

      iex> Cookbook.Recipes.Amount.parse("2 x 400g can")
      {:error, {"can't read this amount, did you mean %{suggestion}?", suggestion: "800 g"}}

  """
  def parse(nil), do: {:ok, {nil, nil}}

  def parse(amount) do
    amount = normalize(amount)

    with nil <- Regex.named_captures(@amount, amount),
         nil <- Regex.named_captures(@multiplied, amount) do
      {:error, {"can't read this amount", []}}
    else
      %{"times" => times, "quantity" => quantity, "unit" => unit} ->
        with {:ok, times} <- parse_quantity(times),
             {:ok, quantity} <- parse_quantity(quantity) do
          suggestion = format(Decimal.mult(times, quantity), normalize_unit(unit))

          {:error,
           {"can't read this amount, did you mean %{suggestion}?", suggestion: suggestion}}
        end

      %{"quantity" => quantity, "unit" => unit} ->
        with {:ok, quantity} <- parse_quantity(quantity) do
          {:ok, {quantity, normalize_unit(unit)}}
        end
    end
  end

  @doc """
  Formats a quantity and unit back into an amount, using fraction glyphs for
  common fractions and a decimal comma otherwise.

  ## Examples

      iex> Cookbook.Recipes.Amount.format(Decimal.new("1.5"), "el")
      "1½ el"

      iex> Cookbook.Recipes.Amount.format(Decimal.new("0.125"), "kg")
      "⅛ kg"

      iex> Cookbook.Recipes.Amount.format(Decimal.new("1.2"), "kg")
      "1,2 kg"

  """
  def format(quantity, unit) do
    [format_quantity(quantity), unit]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  defp format_quantity(nil), do: nil

  defp format_quantity(quantity) do
    quantity = Decimal.round(quantity, @scale)
    whole = Decimal.round(quantity, 0, :down)
    fraction = quantity |> Decimal.sub(whole) |> Decimal.normalize() |> Decimal.to_string(:normal)

    case {Decimal.to_integer(whole), @fraction_glyphs[fraction]} do
      {0, glyph} when is_binary(glyph) ->
        glyph

      {whole, glyph} when is_binary(glyph) ->
        "#{whole}#{glyph}"

      _ ->
        quantity |> Decimal.normalize() |> Decimal.to_string(:normal) |> String.replace(".", ",")
    end
  end

  defp normalize(amount) do
    amount
    |> String.downcase()
    |> String.replace(Map.keys(@fractions), &" #{@fractions[&1]}")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  defp parse_quantity(""), do: {:ok, nil}

  defp parse_quantity(quantity) do
    result =
      case String.split(quantity, [" ", "/"]) do
        [whole, numerator, denominator] -> fraction(numerator, denominator, whole)
        [numerator, denominator] -> fraction(numerator, denominator, "0")
        [decimal] -> decimal |> String.replace(",", ".") |> Decimal.new()
      end

    cond do
      result == :error -> {:error, {"can't divide by 0", []}}
      Decimal.gt?(result, 0) -> {:ok, Decimal.round(result, @scale)}
      true -> {:error, {"must be more than 0", []}}
    end
  end

  defp fraction(_numerator, "0", _whole), do: :error

  defp fraction(numerator, denominator, whole) do
    numerator |> Decimal.new() |> Decimal.div(Decimal.new(denominator)) |> Decimal.add(whole)
  end

  defp normalize_unit(""), do: nil

  defp normalize_unit(unit) do
    unit = unit |> String.trim_trailing(".") |> String.trim()
    Map.get(@unit_aliases, unit, unit)
  end
end
