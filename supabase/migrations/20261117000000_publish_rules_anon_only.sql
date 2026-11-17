-- Publishing is done with the project's publishable key and the publish secret, never by a
-- signed-in player, so players do not need to be able to call it at all.
revoke execute on function public.publish_rules(text, text, jsonb) from authenticated;
