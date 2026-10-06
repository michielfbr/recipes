# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     MyRecipeBook.Repo.insert!(%MyRecipeBook.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias MyRecipeBook.Accounts
alias MyRecipeBook.Accounts.User
alias MyRecipeBook.Repo

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
