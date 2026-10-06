# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Cookbook.Repo.insert!(%Cookbook.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias Cookbook.Accounts
alias Cookbook.Accounts.User
alias Cookbook.Repo

if Mix.env() == :dev do
  email = "test@example.com"
  password = "Toekan1234567!"

  unless Accounts.get_user_by_email(email) do
    %User{}
    |> User.email_changeset(%{email: email})
    |> User.password_changeset(%{password: password})
    |> User.confirm_changeset()
    |> Repo.insert!()

    IO.puts("Seeded dev user #{email} / #{password}")
  end
end
