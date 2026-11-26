defmodule Cookbook.Recipes.Import.URL do
  @moduledoc """
  Checks a recipe URL and removes tracking parameters from it.
  """

  @doc """
  Returns the URL without `utm_*` query parameters.

  Only `http` and `https` URLs with a host are accepted. Other query
  parameters keep their order; the path and fragment are unchanged.

      iex> clean("https://example.com/recept?id=5&utm_source=x")
      {:ok, "https://example.com/recept?id=5"}

      iex> clean("ftp://example.com")
      {:error, :invalid_url}
  """
  @spec clean(String.t()) :: {:ok, String.t()} | {:error, :invalid_url}
  def clean(url) when is_binary(url) do
    case url |> String.trim() |> URI.new() do
      {:ok, %URI{scheme: scheme, host: host} = uri}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        {:ok, uri |> remove_tracking_params() |> URI.to_string()}

      _ ->
        {:error, :invalid_url}
    end
  end

  defp remove_tracking_params(%URI{query: nil} = uri), do: uri

  defp remove_tracking_params(%URI{query: query} = uri) do
    kept =
      query
      |> String.split("&")
      |> Enum.reject(&tracking_param?/1)

    %{uri | query: if(kept == [], do: nil, else: Enum.join(kept, "&"))}
  end

  # Works on the raw pair so the kept parameters stay byte-for-byte the same.
  defp tracking_param?(pair) do
    pair
    |> String.split("=", parts: 2)
    |> hd()
    |> URI.decode_www_form()
    |> String.downcase()
    |> String.starts_with?("utm_")
  end
end
