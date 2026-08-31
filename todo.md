my_recipe_book
|
|- recipe_ingredients - ingredients
|
|-

## recipe

- title
- source
- embeds_many steps
- has_many ingredients

mix phx.gen.live Recipes Recipe recipes title:string instructions:text source:string user_id:references:users

## recipe.steps

- no
- instructions

mix phx.gen.embedded Recipes.Recipe.Step no:integer instructions:text

## recipe_ingedients

- quantity

mix phx.gen.live Recipes RecipeIngredients recipe_ingredients quantity:decimal unit_id:references:units recipe_id:references:recipes ingredient_id:references:ingredients

## ingredients

- name
- name_plural

mix phx.gen.live Ingredients Ingedrient ingredients name:string name_plural:string

## units

- name

mix phx.gen.live Ingredients Unit units name:string
