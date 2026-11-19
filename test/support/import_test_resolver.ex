defmodule Cookbook.Recipes.Import.TestResolver do
  @moduledoc """
  Resolves hosts for `Cookbook.Recipes.Import.Fetcher` in tests, without DNS.

    * IP literals resolve to themselves.
    * `localhost` and hosts ending in `.internal` resolve to private addresses.
    * `unknown.test` does not resolve.
    * Any other host resolves to the public address `203.0.113.10`.
  """

  def resolve("localhost"), do: {:ok, [{127, 0, 0, 1}]}
  def resolve("unknown.test"), do: {:error, :nxdomain}

  def resolve(host) do
    literal =
      host
      |> String.trim_leading("[")
      |> String.trim_trailing("]")
      |> String.to_charlist()
      |> :inet.parse_address()

    case literal do
      {:ok, ip} ->
        {:ok, [ip]}

      {:error, _} ->
        if String.ends_with?(host, ".internal"),
          do: {:ok, [{10, 0, 0, 5}]},
          else: {:ok, [{203, 0, 113, 10}]}
    end
  end
end
