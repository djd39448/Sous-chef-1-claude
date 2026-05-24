-- Align with the original web app's schema: cookbook_recipes.image_url
-- is renamed to thumbnail_url. (`meal_plan_days.image_url` stays — it's
-- our own addition and the original doesn't persist meal-plan-day
-- images at all.) `IF EXISTS` keeps the migration safe to re-run on
-- environments that have already been migrated.

alter table public.cookbook_recipes
    rename column image_url to thumbnail_url;
