defmodule CookbookWeb.UserSessionController do
  use CookbookWeb, :controller

  alias Cookbook.Accounts
  alias Cookbook.RateLimiter
  alias CookbookWeb.UserAuth

  @failed_login_window :timer.minutes(15)
  @failed_logins_per_email 5
  @failed_logins_per_ip 20

  def create(conn, params) do
    create(conn, params, "Welcome back!")
  end

  # email + password login
  defp create(conn, %{"user" => user_params}, info) do
    %{"email" => email, "password" => password} = user_params
    limits = failed_login_limits(conn, email)

    with :ok <- check_limits(limits),
         %Accounts.User{} = user <- Accounts.get_user_by_email_and_password(email, password) do
      conn
      |> put_flash(:info, info)
      |> UserAuth.log_in_user(user, user_params)
    else
      {:error, :rate_limited} ->
        conn
        |> put_flash(:error, "Too many failed log in attempts. Please try again later.")
        |> put_flash(:email, String.slice(email, 0, 160))
        |> redirect(to: ~p"/users/log-in")

      nil ->
        Enum.each(limits, fn {key, _limit} -> RateLimiter.hit(key, @failed_login_window) end)

        # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
        conn
        |> put_flash(:error, "Invalid email or password")
        |> put_flash(:email, String.slice(email, 0, 160))
        |> redirect(to: ~p"/users/log-in")
    end
  end

  # Failed attempts are limited per email (guessing one user's password) and
  # per IP address (guessing many users' passwords).
  defp failed_login_limits(conn, email) do
    email = email |> String.slice(0, 160) |> String.downcase()

    [
      {{:failed_login_email, email}, @failed_logins_per_email},
      {{:failed_login_ip, conn.remote_ip}, @failed_logins_per_ip}
    ]
  end

  defp check_limits(limits) do
    Enum.find_value(limits, :ok, fn {key, limit} ->
      case RateLimiter.check(key, limit, @failed_login_window) do
        :ok -> nil
        error -> error
      end
    end)
  end

  def update_password(conn, %{"user" => user_params} = params) do
    user = conn.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)
    {:ok, {_user, expired_tokens}} = Accounts.update_user_password(user, user_params)

    # disconnect all existing LiveViews with old sessions
    UserAuth.disconnect_sessions(expired_tokens)

    conn
    |> put_session(:user_return_to, ~p"/users/settings")
    |> create(params, "Password updated successfully!")
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end
end
