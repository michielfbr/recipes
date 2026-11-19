# Plan, part 2 of 2: import a recipe from a website URL

**Requires part 1** (`.claude/plans/recipe-import-text/plan.md`): it reuses the OpenRouter client, `Cookbook.Recipes.Import`, the "New" modal and the `/recipes/import` route.

## Goal

A third option in the "New" modal:

- **From website**: paste a URL. The app removes tracking parameters from it, fetches the page, reads the recipe, translates it to Dutch and fills in the normal recipe form. The cleaned URL is stored as the recipe's `source`.

The user reviews the filled-in form and saves it. Nothing is saved automatically.

## Decisions

| Topic | Decision |
|---|---|
| AI | The same as part 1: OpenRouter with Claude Haiku 5.5 and the same JSON schema and prompt. |
| Tracking parameters | Remove every query parameter whose name starts with `utm_` before doing anything else with the URL. All later steps use the cleaned URL. |
| Source | The cleaned URL is stored in the recipe's `source` field. |
| Sites that block us | No workaround (no browser imitation, no headless browser). Show a clear message and offer "From text" from part 1. |

## Site test results (2026-11-17)

| Site | Result | Extraction step that works |
|---|---|---|
| dekrat.nl | 200, schema.org `Recipe` JSON-LD | 1, JSON-LD (about 600 tokens; no `cookTime`) |
| picnic.app | 200, Next.js, no JSON-LD | 3 for ingredients, 4 for steps (steps are only in `self.__next_f` scripts) |
| ah.nl | 403 Access Denied (Akamai) | None: show the "blocked" message and offer "From text" |

## How it works

```
URL ──► remove utm_ params ──► Fetcher ──► HTML ──► Extractor ──► small text or JSON ──► OpenRouter (Haiku) ──► JSON ──► form params (+ source) ──► RecipeLive.Form
```

The extractor stops at the first step that finds a recipe:

1. **JSON-LD**: the object with `@type: "Recipe"`, which may be inside `@graph` or have a list as `@type`. Keep only `name`, `recipeIngredient`, `recipeInstructions`, `totalTime`, `cookTime`, `prepTime` and `recipeYield`.
2. **Microdata**: the text of the `itemprop="recipeIngredient"`, `itemprop="recipeInstructions"` and similar elements.
3. **Cleaned text**:
   - Remove `script`, `style`, `noscript`, `svg`, `iframe`, `nav`, `header`, `footer`, `aside`, `form` and `template`.
   - Narrow down to `<main>` or `<article>` if the page has one.
   - Convert to plain text with line breaks, and prefix list items with `- `.
   - Collapse whitespace.
4. **Script text**: used together with step 3 when the cleaned text looks too short to hold the steps. Take string literals from inline `<script>` tags that are 40 or more characters long, contain at least 6 spaces, are more than 85% letters and spaces, and contain no URLs or code characters. Remove duplicates.

Cap the input sent to the AI at about 15,000 characters.

---

## Steps

Each step ends in a working, tested state. Run `mix precommit` after each step.

### Step 1: Clean and check the URL

New module `Cookbook.Recipes.Import.URL` with `clean(url) :: {:ok, String.t()} | {:error, :invalid_url}`.

- [x] Trim whitespace and parse with `URI.new/1`. Accept only `http` and `https` URLs with a host; anything else becomes `{:error, :invalid_url}`.
- [x] Remove every query parameter whose name starts with `utm_` (for example `utm_source`, `utm_medium`, `utm_campaign`, `utm_term`, `utm_content`). Keep all other parameters in their original order. Drop the `?` when no parameters are left.
- [x] Keep the path and fragment unchanged.
- [x] Tests:
  - `https://example.com/recept?utm_source=nieuwsbrief&utm_medium=email` becomes `https://example.com/recept`.
  - `https://example.com/recept?id=5&utm_campaign=x&page=2` becomes `https://example.com/recept?id=5&page=2`.
  - A URL without parameters is unchanged.
  - `ftp://example.com` and `not a url` give `:invalid_url`.

### Step 2: Fetch pages safely

New module `Cookbook.Recipes.Import.Fetcher` with `fetch(url) :: {:ok, html} | {:error, reason}`. It receives the cleaned URL from step 1.

- [ ] SSRF protection: resolve the host and reject loopback, private, link-local and similar addresses (`127.0.0.0/8`, `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, `169.254.0.0/16`, `::1`, `fc00::/7`, `fe80::/10`, `0.0.0.0`).
- [ ] Follow at most 3 redirects by hand (`redirect: false`), checking every new address the same way.
- [ ] Use a 10-second timeout and a 3 MB size limit (the Picnic page is 763 KB).
- [ ] Use an honest User-Agent, such as `Cookbook recipe importer`.
- [ ] Map failures to error reasons:
  - `:blocked` (403 or 429)
  - `:not_found` (404)
  - `:unreachable` (DNS failure, timeout or 5xx)
  - `:too_large`
  - `:not_html`
- [ ] Tests use `Req.Test` stubs and cover: success, a redirect to a private IP being rejected, 403 becoming `:blocked`, and the size limit.

### Step 3: Extract the recipe from HTML

New module `Cookbook.Recipes.Import.Extractor` with `extract(html) :: {:ok, {:json_ld | :microdata | :text, content}} | {:error, :no_recipe}`.

- [ ] Move `lazy_html` from `only: :test` to a runtime dependency in `mix.exs`.
- [ ] Implement extraction steps 1 to 4 from "How it works".
- [ ] Return `{:error, :no_recipe}` when the result is too short to be a recipe (for example, under 200 characters).
- [ ] Save fixtures in `test/support/fixtures/recipe_pages/`: `dekrat.html` (JSON-LD) and `picnic.html` (script text). Download them again from the URLs in "Site test results"; the earlier copies were in a temporary folder.
- [ ] Tests:
  - De Krat gives `:json_ld` with 14 ingredients and no image or author fields.
  - Picnic gives `:text` that contains both "chorizoworst" and "Kook ondertussen 300 g fusilli".
  - A page with only navigation gives `:no_recipe`.

### Step 4: Import from a URL

Add `from_url(scope, url) :: {:ok, params} | {:error, reason}` to `Cookbook.Recipes.Import` from part 1.

- [ ] The order is: `URL.clean/1`, then `Fetcher.fetch/1`, then `Extractor.extract/1`, then `OpenRouter.extract_recipe/2`. Build the params the same way as `from_text/2`.
- [ ] Set `"source"` in the params to the cleaned URL, so it's saved with the recipe and shows in the form's source field.
- [ ] Tests run `from_url/2` end to end with stubbed HTTP and check:
  - A URL with `utm_` parameters is fetched without them (assert on the request the stub receives).
  - `"source"` holds the cleaned URL.
  - Errors from each stage come through unchanged.

### Step 5: "From website" in the New modal

Edit `lib/cookbook_web/live/recipe_live/index.ex`.

- [ ] Add a **From website** card (`id="new-from-website"`) to the modal from part 1, as the first option.
- [ ] Clicking it reveals a URL field and an "Import" button in the modal. The field gets focus when it appears.
- [ ] Submitting goes to `/recipes/import?url=…`.
- [ ] Tests: the third card is present, and submitting a URL navigates to the import route with the URL.

### Step 6: URL import on the recipe form

Edit `lib/cookbook_web/live/recipe_live/form.ex`.

- [ ] Add `apply_action(socket, :import, %{"url" => url})` next to the text version from part 1:
  - Run `Import.from_url/2` in the background with `start_async`.
  - While it runs, show "Reading recipe from {host}…" with the same loading state as part 1.
- [ ] Success works the same as a text import, plus the `source` field is filled with the cleaned URL.
- [ ] When the import fails, show a message with buttons for **Paste text instead** (goes to `/recipes/import`) and **Start from scratch**:

  | Error | Message |
  |---|---|
  | `:invalid_url` | "That doesn't look like a web address." |
  | `:blocked` | "This site doesn't allow importing. Copy the recipe text and use 'From text'." |
  | `:no_recipe` | "No recipe found on this page." |
  | `:unreachable`, `:not_found` | "Couldn't open this page." |
  | `:too_large`, `:not_html` | "This page can't be imported." |
  | AI errors | The same messages as part 1. |

- [ ] Tests use stubbed HTTP and check:
  - The URL import shows the loading state, then a filled form with the cleaned URL in the source field.
  - The 403 path shows the blocked message and the "paste text" button.
  - Saving creates the recipe with `source` set to the cleaned URL, without `utm_` parameters.

### Step 7: Polish and finish

- [ ] Check the loading state, the error states and the modal on mobile width.
- [ ] Manual check with a real API key against the three test sites, including one URL with `utm_` parameters.
- [ ] Run `mix precommit` and make sure it passes cleanly.

## Out of scope for now

- A bookmarklet that sends a page from the user's browser (could help with AH later).
- Removing other tracking parameters, such as `fbclid` or `gclid`. Easy to add to `URL.clean/1` later.
- Importing images.
- Caching imports by URL.
