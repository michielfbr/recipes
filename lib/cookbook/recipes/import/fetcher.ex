defmodule Cookbook.Recipes.Import.Fetcher do
  @moduledoc """
  Fetches a web page for a recipe import.

  The URL comes from a user, so the fetcher only connects to public
  addresses. It resolves the host itself, rejects private and local
  addresses, and connects to the address it checked. Redirects are followed
  by hand so every hop is checked the same way.

  ## Configuration

      config :cookbook, Cookbook.Recipes.Import.Fetcher,
        plug: {Req.Test, Cookbook.Recipes.Import.Fetcher},
        resolver: MyResolver

  `:resolver` is a module with `resolve(host) :: {:ok, [:inet.ip_address()]} |
  {:error, term()}`. It defaults to DNS through `:inet`.
  """

  import Bitwise

  require Logger

  @max_redirects 3
  @max_bytes 3_000_000
  @timeout 10_000
  @user_agent "Cookbook recipe importer"
  @redirect_statuses [301, 302, 303, 307, 308]

  @type error :: :blocked | :not_found | :unreachable | :too_large | :not_html

  @doc """
  Fetches the HTML of the page at `url`.

  Follows at most #{@max_redirects} redirects, gives up after
  #{div(@timeout, 1000)} seconds and refuses pages larger than
  #{div(@max_bytes, 1_000_000)} MB.
  """
  @spec fetch(String.t()) :: {:ok, String.t()} | {:error, error()}
  def fetch(url) when is_binary(url) do
    deadline = System.monotonic_time(:millisecond) + @timeout
    fetch_uri(URI.parse(url), @max_redirects, deadline)
  end

  defp fetch_uri(%URI{scheme: scheme, host: host} = uri, redirects_left, deadline)
       when scheme in ["http", "https"] and is_binary(host) and host != "" do
    with {:ok, ip} <- resolve_public(host),
         {:ok, response} <- request(uri, ip, deadline) do
      handle_response(response, uri, redirects_left, deadline)
    end
  end

  defp fetch_uri(uri, _redirects_left, _deadline) do
    Logger.info("Recipe import: not following URL #{inspect(URI.to_string(uri))}")
    {:error, :unreachable}
  end

  defp handle_response(%Req.Response{private: %{too_large: true}}, _uri, _left, _deadline) do
    {:error, :too_large}
  end

  defp handle_response(%Req.Response{status: 200} = response, _uri, _left, _deadline) do
    if html?(response), do: {:ok, response.body}, else: {:error, :not_html}
  end

  defp handle_response(%Req.Response{status: status} = response, uri, left, deadline)
       when status in @redirect_statuses do
    case Req.Response.get_header(response, "location") do
      [location | _] when left > 0 ->
        uri |> URI.merge(location) |> fetch_uri(left - 1, deadline)

      [_ | _] ->
        Logger.info("Recipe import: too many redirects for #{URI.to_string(uri)}")
        {:error, :unreachable}

      [] ->
        {:error, :unreachable}
    end
  end

  defp handle_response(%Req.Response{status: status}, _uri, _left, _deadline)
       when status in [401, 403, 429],
       do: {:error, :blocked}

  defp handle_response(%Req.Response{status: status}, _uri, _left, _deadline)
       when status in [404, 410],
       do: {:error, :not_found}

  defp handle_response(%Req.Response{status: status}, uri, _left, _deadline) do
    Logger.info("Recipe import: #{URI.to_string(uri)} returned #{status}")
    {:error, :unreachable}
  end

  defp html?(response) do
    case Req.Response.get_header(response, "content-type") do
      [] -> true
      [type | _] -> String.contains?(type, ["text/html", "application/xhtml+xml"])
    end
  end

  defp request(uri, ip, deadline) do
    config = Application.get_env(:cookbook, __MODULE__, [])

    [
      # Connect to the checked address; `hostname` keeps TLS verification,
      # SNI and the Host header on the real host.
      url: %{uri | host: ip |> :inet.ntoa() |> to_string()},
      headers: [
        host: authority(uri),
        user_agent: @user_agent,
        accept: "text/html,application/xhtml+xml",
        accept_language: "nl,en;q=0.8"
      ],
      # A pool per host (Req can't combine :finch with :connect_options);
      # idle pools shut down after a minute.
      finch: [
        conn_opts: [hostname: uri.host, transport_opts: [timeout: @timeout]],
        pool_max_idle_time: 60_000
      ],
      receive_timeout: @timeout,
      redirect: false,
      retry: false,
      compressed: false,
      decode_body: false,
      into: &collect(&1, &2, deadline)
    ]
    |> Keyword.merge(Keyword.take(config, [:plug]))
    |> Req.request()
    |> case do
      {:ok, response} ->
        {:ok, response}

      {:error, exception} ->
        Logger.info(
          "Recipe import: #{URI.to_string(uri)} failed: #{Exception.message(exception)}"
        )

        {:error, :unreachable}
    end
  end

  defp authority(%URI{host: host, port: port, scheme: scheme}) do
    if port == URI.default_port(scheme), do: host, else: "#{host}:#{port}"
  end

  # Collects the body, and stops early when it gets too large or too slow.
  defp collect({:data, data}, {request, response}, deadline) do
    body = response.body <> data

    cond do
      byte_size(body) > @max_bytes ->
        {:halt, {request, Req.Response.put_private(%{response | body: ""}, :too_large, true)}}

      System.monotonic_time(:millisecond) > deadline ->
        {:halt, {request, %{response | status: 504, body: ""}}}

      true ->
        {:cont, {request, %{response | body: body}}}
    end
  end

  defp resolve_public(host) do
    resolver = Application.get_env(:cookbook, __MODULE__, [])[:resolver] || __MODULE__

    case resolver.resolve(host) do
      {:ok, [_ | _] = ips} ->
        if Enum.all?(ips, &public_ip?/1) do
          {:ok, Enum.find(ips, hd(ips), &(tuple_size(&1) == 4))}
        else
          Logger.warning("Recipe import: refusing non-public address for #{host}")
          {:error, :unreachable}
        end

      _ ->
        {:error, :unreachable}
    end
  end

  @doc false
  # Default resolver: IP literals as-is, otherwise DNS (IPv4 and IPv6).
  def resolve(host) do
    host = host |> String.trim_leading("[") |> String.trim_trailing("]") |> String.to_charlist()

    case :inet.parse_address(host) do
      {:ok, ip} ->
        {:ok, [ip]}

      {:error, _} ->
        ips =
          for family <- [:inet, :inet6],
              {:ok, ips} <- [:inet.getaddrs(host, family, @timeout)],
              ip <- ips,
              do: ip

        if ips == [], do: {:error, :nxdomain}, else: {:ok, ips}
    end
  end

  @doc false
  @spec public_ip?(:inet.ip_address()) :: boolean()
  def public_ip?({a, b, _, _} = ip) do
    not (a == 0 or
           a == 10 or
           a == 127 or
           (a == 100 and b in 64..127) or
           (a == 169 and b == 254) or
           (a == 172 and b in 16..31) or
           (a == 192 and b == 168) or
           a >= 224 or
           ip == {192, 0, 0, 0})
  end

  # IPv4-mapped (::ffff:a.b.c.d) and IPv4-compatible addresses: check the IPv4 part.
  def public_ip?({0, 0, 0, 0, 0, x, g, h}) when x in [0, 0xFFFF] and (g != 0 or h > 1) do
    public_ip?({g >>> 8, g &&& 0xFF, h >>> 8, h &&& 0xFF})
  end

  def public_ip?({a, _, _, _, _, _, _, _} = ip) do
    not (ip in [{0, 0, 0, 0, 0, 0, 0, 0}, {0, 0, 0, 0, 0, 0, 0, 1}] or
           (a &&& 0xFE00) == 0xFC00 or
           (a &&& 0xFFC0) == 0xFE80 or
           (a &&& 0xFF00) == 0xFF00)
  end
end
