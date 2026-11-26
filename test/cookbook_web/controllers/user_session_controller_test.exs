defmodule CookbookWeb.UserSessionControllerTest do
  use CookbookWeb.ConnCase, async: true

  import Cookbook.AccountsFixtures

  setup do
    %{user: user_fixture()}
  end

  describe "POST /users/log-in - email and password" do
    test "logs the user in", %{conn: conn, user: user} do
      user = set_password(user)

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/recipes"

      # Now do a logged in request and assert on the menu
      conn = get(conn, ~p"/")
      response = html_response(conn, 200)
      assert response =~ user.email
      assert response =~ ~p"/users/settings"
      assert response =~ ~p"/users/log-out"
    end

    test "logs the user in with remember me", %{conn: conn, user: user} do
      user = set_password(user)

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password(),
            "remember_me" => "true"
          }
        })

      assert conn.resp_cookies["_cookbook_web_user_remember_me"]
      assert redirected_to(conn) == ~p"/recipes"
    end

    test "logs the user in with return to", %{conn: conn, user: user} do
      user = set_password(user)

      conn =
        conn
        |> init_test_session(user_return_to: "/foo/bar")
        |> post(~p"/users/log-in", %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password()
          }
        })

      assert redirected_to(conn) == "/foo/bar"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Welcome back!"
    end

    test "redirects to login page with invalid credentials", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/users/log-in?mode=password", %{
          "user" => %{"email" => user.email, "password" => "invalid_password"}
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"
      assert redirected_to(conn) == ~p"/users/log-in"
    end
  end

  describe "POST /users/log-in - failed attempts" do
    # A unique IP per test, so the per-IP limit doesn't affect other tests.
    setup %{conn: conn} do
      %{conn: %{conn | remote_ip: {10, 0, 0, System.unique_integer([:positive])}}}
    end

    test "refuses the right password after 5 failed attempts for an email", %{
      conn: conn,
      user: user
    } do
      user = set_password(user)

      for _ <- 1..5 do
        conn = log_in(conn, user.email, "invalid_password")
        assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"
      end

      conn = log_in(conn, String.upcase(user.email), valid_user_password())

      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Too many failed log in attempts"
      assert redirected_to(conn) == ~p"/users/log-in"
    end

    test "refuses log in after 20 failed attempts from an IP address", %{
      conn: conn,
      user: user
    } do
      user = set_password(user)

      for _ <- 1..20 do
        log_in(conn, unique_user_email(), "invalid_password")
      end

      conn = log_in(conn, user.email, valid_user_password())

      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Too many failed log in attempts"
    end

    test "still logs in after fewer failed attempts", %{conn: conn, user: user} do
      user = set_password(user)

      for _ <- 1..4 do
        log_in(conn, user.email, "invalid_password")
      end

      conn = log_in(conn, user.email, valid_user_password())

      assert get_session(conn, :user_token)
    end

    defp log_in(conn, email, password) do
      post(conn, ~p"/users/log-in", %{"user" => %{"email" => email, "password" => password}})
    end
  end

  describe "DELETE /users/log-out" do
    test "logs the user out", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> delete(~p"/users/log-out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"
    end

    test "succeeds even if the user is not logged in", %{conn: conn} do
      conn = delete(conn, ~p"/users/log-out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"
    end
  end
end
