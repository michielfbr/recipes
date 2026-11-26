defmodule CookbookWeb.ContentSecurityPolicy do
  @moduledoc """
  Sets the `content-security-policy` header, which tells the browser to only
  load scripts, styles, images and connections from this app.

  Inline scripts are only run when they carry the nonce of the request,
  which is assigned as `@csp_nonce`:

      <script nonce={@csp_nonce}>...</script>

  Inline styles stay allowed, as LiveView and the dev tools use them.
  """

  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    nonce = 18 |> :crypto.strong_rand_bytes() |> Base.encode64()

    conn
    |> assign(:csp_nonce, nonce)
    |> put_resp_header("content-security-policy", policy(nonce))
  end

  defp policy(nonce) do
    Enum.join(
      [
        "default-src 'self'",
        "script-src 'self' 'nonce-#{nonce}'",
        "style-src 'self' 'unsafe-inline'",
        "img-src 'self' data:",
        "font-src 'self' data:",
        "connect-src 'self'",
        "object-src 'none'",
        "base-uri 'self'",
        "form-action 'self'",
        "frame-ancestors 'none'"
      ],
      "; "
    )
  end
end
