# Tide & Timber for browsers

## Play

Open the GitHub Pages site in a current phone, tablet, or desktop browser. Both seats start with editable 30-card starters. Open **Browse** to inspect every illustrated design in your faction. Use **+** and **−** to tag 20–30 cards for a match, or start from **20-card starter** or **Random 20**. The **Tagged** filter shows your selections. Each player opens with five cards. For a duel, choose **Two players**, then **Create room**. Share the six-character code with a LÖVE player, or send the room link to another browser player. The guest chooses a deck and selects **Join room**.

Tap a hand card to inspect it. **Choose placement** highlights the available Front and Back row positions. **Play effect** resolves an effect. Swipe across crowded rows and the hand to see additional cards. Every unit displays current HP. Open **Rows & Bridge** for a worked example. Placement markers show row bonuses, Bridge endpoints, and the chains your placement would form. Ability dialogs list the choices supplied by the server. Close a dialog to inspect the table and use **Resolve ability** to reopen it.

**Return to your match in progress** restores your seat when you reopen the same site in the same browser profile. Clearing site data removes the anonymous identity. **Leave match** closes the match for both seats.

## Build and preview

From the project root, with Node.js 22, Python 3 and Lua 5.4 on your PATH, run

```sh
npm ci --prefix web
python3 web/build.py
node web/tests/protocol.mjs
python3 -m http.server 4173 --bind 127.0.0.1 --directory web/dist
```

Open [the local preview](http://127.0.0.1:4173/). It uses the project URL and publishable key from `online/config.lua`. Browser requests require the CORS-enabled function below.

Each build executes `tabletop.library` to generate the illustrated collections, copy limits, featured cards, and starter decks. It copies the mapped artwork, fonts and licenses into `web/dist/`. The rules hash comes from the same manifest and digest function as `scripts/publish_rules.py`. Fengari runs the desktop mirror and public-state Lua helpers to display legal plays, chains and strength. Supabase deals the cards, resolves every move and serves each seat its own view.

The protocol test uses the repository's local Lua server harness. It exercises both seats, sign-in renewal, reloads, missing requests, lost replies, and a complete match against the computer.

## Enable browser requests

The Edge Function change adds CORS headers to responses and answers unauthenticated preflight requests. The function still checks the player's bearer token on game requests. From the project root, with a signed-in Supabase CLI v2, run

```sh
npx supabase@2 functions deploy game --project-ref tourlytmhcioxjiwsnxi --use-api
```

This uses the existing `supabase/config.toml`. The CORS change needs only the function deployment. Card or rule changes still follow the project's existing rules-publishing process.

To check the deployed function, run

```sh
curl -i -X OPTIONS https://tourlytmhcioxjiwsnxi.supabase.co/functions/v1/game \
  -H 'Origin: https://example.github.io' \
  -H 'Access-Control-Request-Method: POST' \
  -H 'Access-Control-Request-Headers: apikey, authorization, content-type'
```

Expect HTTP 204, an allowed origin of `*`, and headers allowing `POST`, `apikey`, `authorization` and `content-type`.

## Publish to GitHub Pages

1. Put the project in the target GitHub repository. Before committing, run `git check-ignore -v supabase/.publish_secret` and verify that `git ls-files -- supabase/.publish_secret` returns no paths.
2. In **Settings → Pages → Build and deployment → Source**, select **GitHub Actions**.
3. Push to `main`, or run **Deploy browser game** under **Actions**. The workflow builds and tests the browser client, then uploads only `web/dist/`.
4. Open the URL reported by the deployment job. It normally has the form `https://USERNAME.github.io/REPOSITORY/`. Assets use relative URLs and room links use `?room=CODE`, so refreshing either URL works at the repository subpath.
