defmodule Cookbook.Recipes.Import.FetcherTest do
  use ExUnit.Case, async: true

  alias Cookbook.Recipes.Import.Fetcher

  @moduletag :capture_log

  @html "<html><body><h1>Pannenkoeken</h1></body></html>"

  defp stub(fun), do: Req.Test.stub(Fetcher, fun)

  defp html(conn, body \\ @html) do
    conn
    |> Plug.Conn.put_resp_content_type("text/html")
    |> Plug.Conn.send_resp(200, body)
  end

  defp redirect(conn, location) do
    conn
    |> Plug.Conn.put_resp_header("location", location)
    |> Plug.Conn.send_resp(302, "")
  end

  describe "fetch/1" do
    test "returns the HTML and sends an honest User-Agent and the real host" do
      test_pid = self()

      stub(fn conn ->
        send(test_pid, {:request, conn})
        html(conn)
      end)

      assert Fetcher.fetch("https://www.dekrat.nl/recepten/pasta?id=5") == {:ok, @html}

      assert_receive {:request, conn}
      # Connects to the address it checked, with the real host in the Host header.
      assert conn.host == "203.0.113.10"
      assert conn.request_path == "/recepten/pasta"
      assert conn.query_string == "id=5"
      assert Plug.Conn.get_req_header(conn, "host") == ["www.dekrat.nl"]
      assert Plug.Conn.get_req_header(conn, "user-agent") == ["Cookbook recipe importer"]
    end

    test "follows redirects to public addresses" do
      stub(fn
        %{request_path: "/old"} = conn -> redirect(conn, "/new")
        %{request_path: "/new"} = conn -> html(conn)
      end)

      assert Fetcher.fetch("https://example.com/old") == {:ok, @html}
    end

    test "rejects a redirect to a private address" do
      test_pid = self()

      stub(fn conn ->
        send(test_pid, {:request, conn.host})
        redirect(conn, "http://admin.internal/secrets")
      end)

      assert Fetcher.fetch("https://example.com/recept") == {:error, :unreachable}
      assert_receive {:request, "203.0.113.10"}
      refute_receive {:request, _}
    end

    test "rejects private, loopback and link-local addresses without a request" do
      stub(fn _conn -> flunk("should not connect") end)

      for url <- [
            "http://localhost:4000/",
            "http://127.0.0.1/",
            "http://10.1.2.3/",
            "http://172.16.0.1/",
            "http://192.168.1.1/",
            "http://169.254.169.254/latest/meta-data",
            "http://0.0.0.0/",
            "http://[::1]/",
            "http://[fd00::1]/",
            "http://[fe80::1]/",
            "http://[::ffff:127.0.0.1]/"
          ] do
        assert Fetcher.fetch(url) == {:error, :unreachable}, url
      end
    end

    test "follows at most 3 redirects" do
      stub(fn conn ->
        n = String.to_integer(String.trim_leading(conn.request_path, "/"))
        redirect(conn, "/#{n + 1}")
      end)

      assert Fetcher.fetch("https://example.com/0") == {:error, :unreachable}
    end

    test "maps 403 and 429 to :blocked" do
      stub(&Plug.Conn.send_resp(&1, 403, "Access Denied"))
      assert Fetcher.fetch("https://www.ah.nl/allerhande/recept") == {:error, :blocked}

      stub(&Plug.Conn.send_resp(&1, 429, "Slow down"))
      assert Fetcher.fetch("https://www.ah.nl/allerhande/recept") == {:error, :blocked}
    end

    test "maps 404 to :not_found and 5xx to :unreachable" do
      stub(&Plug.Conn.send_resp(&1, 404, "Not found"))
      assert Fetcher.fetch("https://example.com/weg") == {:error, :not_found}

      stub(&Plug.Conn.send_resp(&1, 503, "Down"))
      assert Fetcher.fetch("https://example.com/") == {:error, :unreachable}
    end

    test "maps connection errors and unknown hosts to :unreachable" do
      stub(&Req.Test.transport_error(&1, :timeout))
      assert Fetcher.fetch("https://example.com/") == {:error, :unreachable}

      assert Fetcher.fetch("https://unknown.test/") == {:error, :unreachable}
    end

    test "refuses pages larger than 3 MB" do
      stub(&html(&1, String.duplicate("a", 3_000_001)))
      assert Fetcher.fetch("https://example.com/") == {:error, :too_large}

      stub(&html(&1, String.duplicate("a", 3_000_000)))
      assert {:ok, _html} = Fetcher.fetch("https://example.com/")
    end

    test "refuses responses that are not HTML" do
      stub(&Req.Test.json(&1, %{"recipe" => "nope"}))
      assert Fetcher.fetch("https://example.com/api") == {:error, :not_html}
    end
  end

  describe "public_ip?/1" do
    test "accepts public addresses" do
      assert Fetcher.public_ip?({93, 184, 216, 34})
      assert Fetcher.public_ip?({172, 32, 0, 1})
      assert Fetcher.public_ip?({0x2A00, 0x1450, 0, 0, 0, 0, 0, 0x200E})
    end
  end
end
