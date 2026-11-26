defmodule CookbookWeb.ContentSecurityPolicyTest do
  use CookbookWeb.ConnCase, async: true

  for path <- ["/", "/users/log-in"] do
    test "#{path} allows only the inline script with the request's nonce", %{conn: conn} do
      conn = get(conn, unquote(path))

      [policy] = get_resp_header(conn, "content-security-policy")
      [_, nonce] = Regex.run(~r/script-src 'self' 'nonce-([^']+)'/, policy)

      assert policy =~ "default-src 'self'"
      assert policy =~ "frame-ancestors 'none'"

      inline_scripts =
        conn
        |> html_response(200)
        |> LazyHTML.from_document()
        |> LazyHTML.query("script:not([src])")

      assert Enum.count(inline_scripts) > 0
      assert LazyHTML.attribute(inline_scripts, "nonce") |> Enum.uniq() == [nonce]
    end
  end

  test "uses a new nonce for every request", %{conn: conn} do
    [policy1] = conn |> get(~p"/") |> get_resp_header("content-security-policy")
    [policy2] = build_conn() |> get(~p"/") |> get_resp_header("content-security-policy")

    refute policy1 == policy2
  end
end
