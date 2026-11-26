defmodule CookbookWeb.UserLive.LoginTest do
  use CookbookWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Cookbook.AccountsFixtures

  describe "login page" do
    test "renders login page", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/users/log-in")

      assert html =~ "Log in"
      assert has_element?(lv, "#login_form_password")
      refute has_element?(lv, "#login_form_magic")
    end
  end

  describe "user login - password" do
    test "logs in and stays logged in with valid credentials", %{conn: conn} do
      user = user_fixture() |> set_password()

      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      assert has_element?(lv, "#login-button")
      refute has_element?(lv, "#login_form_password button:not(#login-button)")
      assert has_element?(lv, "#user_remember_me[checked]")

      form =
        form(lv, "#login_form_password",
          user: %{email: user.email, password: valid_user_password(), remember_me: true}
        )

      conn = submit_form(form, conn)

      assert redirected_to(conn) == ~p"/recipes"
      assert conn.resp_cookies["_cookbook_web_user_remember_me"]
    end

    test "logs in only for the session when stay logged in is unchecked", %{conn: conn} do
      user = user_fixture() |> set_password()

      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      form =
        form(lv, "#login_form_password",
          user: %{email: user.email, password: valid_user_password(), remember_me: false}
        )

      conn = submit_form(form, conn)

      assert redirected_to(conn) == ~p"/recipes"
      assert get_session(conn, :user_token)
      refute conn.resp_cookies["_cookbook_web_user_remember_me"]
    end

    test "redirects to login page with a flash error if credentials are invalid", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      form =
        form(lv, "#login_form_password", user: %{email: "test@email.com", password: "123456"})

      render_submit(form, %{user: %{remember_me: true}})

      conn = follow_trigger_action(form, conn)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"
      assert redirected_to(conn) == ~p"/users/log-in"
    end
  end

  describe "login navigation" do
    test "has no link to a registration page", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      refute has_element?(lv, ~s{a[href="/users/register"]})
    end
  end

  describe "re-authentication (sudo mode)" do
    setup %{conn: conn} do
      user = user_fixture()
      %{user: user, conn: log_in_user(conn, user)}
    end

    test "shows login page with email filled in", %{conn: conn, user: user} do
      {:ok, _lv, html} = live(conn, ~p"/users/log-in")

      assert html =~ "You need to reauthenticate"

      assert html =~
               ~s(<input type="email" name="user[email]" id="login_form_password_email" value="#{user.email}")
    end
  end
end
