# Cookbook

A tool to save, edit and browse through the recipes you collect.

This is a rebuild of the React/Express JS project I built years ago.

To start your Phoenix server:

- Start the database with `docker compose up -d`
- Run `mix setup` to install and setup dependencies
- Load the secrets from 1Password with `source secrets`
- Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## Environment variables

| Variable | Required | Description |
|---|---|---|
| `OPENROUTER_API_KEY` | Yes, except in tests | [OpenRouter](https://openrouter.ai/settings/keys) API key, used to import recipes from text. The app doesn't start without it. |
| `RECIPE_IMPORT_MODEL` | No | OpenRouter model used for importing recipes. Defaults to `anthropic/claude-haiku-5.5`. |

In production, `DATABASE_URL`, `SECRET_KEY_BASE` and `PHX_HOST` are needed as well.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Learn more

- Official website: https://www.phoenixframework.org/
- Guides: https://hexdocs.pm/phoenix/overview.html
- Docs: https://hexdocs.pm/phoenix
- Forum: https://elixirforum.com/c/phoenix-forum
- Source: https://github.com/phoenixframework/phoenix
