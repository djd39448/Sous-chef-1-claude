-- Persist generated recipe images on the rows themselves so they stick
-- with the meal/recipe forever (until the user regenerates). The column
-- holds a `data:image/png;base64,…` URL emitted by gpt-image-1; the iOS
-- client decodes it into a UIImage. Nullable — null means "no image
-- generated yet; show the Tap-to-generate placeholder."

alter table public.meal_plan_days
    add column if not exists image_url text;

alter table public.cookbook_recipes
    add column if not exists image_url text;
