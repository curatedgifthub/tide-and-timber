// Tide & Timber "game" Edge Function.
//
// The rules of the card game are the project's own Lua files. They are published to the
// `rules` table (scripts/publish_rules.py) and run here in fengari, a Lua VM written in
// JavaScript, so the server plays by exactly the code the game ships with. This file only
// does what Lua cannot: check who is calling, read and write the match row, and make sure a
// move is applied once. See online/server.lua for the match logic.
import { createClient } from "npm:@supabase/supabase-js@2.45.4";
import fengari from "npm:fengari@0.1.4";

const { lua, lauxlib, lualib, to_luastring } = fengari;
const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false, autoRefreshToken: false },
});

type Engine = { version: string; L: unknown };
let engine: Engine | null = null;

// The newest published rules, compiled once per function instance.
async function rules(): Promise<Engine> {
  const newest = await admin.from("rules").select("version").order("published_at", { ascending: false }).limit(1).maybeSingle();
  if (newest.error) throw new Error(newest.error.message);
  if (!newest.data) throw new Error("No rules have been published. Run scripts/publish_rules.py.");
  if (engine && engine.version === newest.data.version) return engine;
  const full = await admin.from("rules").select("version, modules").eq("version", newest.data.version).single();
  if (full.error) throw new Error(full.error.message);
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  lua.lua_getglobal(L, to_luastring("package"));
  lua.lua_getfield(L, -1, to_luastring("preload"));
  for (const [name, source] of Object.entries(full.data.modules as Record<string, string>)) {
    const chunk = to_luastring(source);
    if (lauxlib.luaL_loadbuffer(L, chunk, chunk.length, to_luastring("@" + name)) !== lua.LUA_OK) {
      throw new Error("Rules module " + name + ": " + lua.lua_tojsstring(L, -1));
    }
    lua.lua_setfield(L, -2, to_luastring(name));
  }
  lua.lua_settop(L, 0);
  const boot = to_luastring("local server=require('online.server') server.version=... tt_call=server.call");
  if (lauxlib.luaL_loadbuffer(L, boot, boot.length, to_luastring("=boot")) !== lua.LUA_OK) throw new Error(lua.lua_tojsstring(L, -1));
  lua.lua_pushstring(L, to_luastring(full.data.version));
  if (lua.lua_pcall(L, 1, 0, 0) !== lua.LUA_OK) throw new Error("Rules failed to load: " + lua.lua_tojsstring(L, -1));
  engine = { version: full.data.version, L };
  return engine;
}

// Server.call(request_json, snapshot) -> response_json, new_snapshot_or_nil
function run(e: Engine, request: unknown, snapshot: string | null): { resp: any; snapshot: string | null } {
  const L = e.L;
  lua.lua_settop(L, 0);
  lua.lua_getglobal(L, to_luastring("tt_call"));
  lua.lua_pushstring(L, to_luastring(JSON.stringify(request)));
  if (snapshot === null) lua.lua_pushnil(L);
  else lua.lua_pushstring(L, to_luastring(snapshot));
  if (lua.lua_pcall(L, 2, 2, 0) !== lua.LUA_OK) {
    const message = lua.lua_tojsstring(L, -1);
    lua.lua_settop(L, 0);
    throw new Error(message);
  }
  const text = lua.lua_tojsstring(L, -2);
  const next = lua.lua_isnil(L, -1) ? null : lua.lua_tojsstring(L, -1);
  lua.lua_settop(L, 0);
  return { resp: JSON.parse(text), snapshot: next };
}

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
};
const answer = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
const refuse = (error: string, message: string, extra: Record<string, unknown> = {}) =>
  answer({ ok: false, error, message, ...extra });

// A seed for the deterministic shuffle. It never leaves the server.
function seed(): number {
  const buffer = new Uint32Array(1);
  crypto.getRandomValues(buffer);
  return (buffer[0] % 2147483646) + 1;
}
const ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // no 0/O or 1/I
function roomCode(): string {
  const bytes = new Uint8Array(6);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (b) => ALPHABET[b & 31]).join("");
}

const COLUMNS = "id, host, guest, mode, status, seq, rules, config, pending, snapshot, last_action, log_count";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
  try {
    if (req.method !== "POST") return answer({ message: "POST only" }, 405);
    const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
    const who = token ? await admin.auth.getUser(token) : null;
    if (!who || who.error || !who.data?.user) return answer({ message: "Sign-in required" }, 401);
    const user = who.data.user.id;

    let body: any;
    try {
      body = await req.json();
    } catch {
      return refuse("bad_request", "The request is not valid JSON.");
    }
    if (typeof body !== "object" || body === null) return refuse("bad_request", "The request is not valid.");
    const e = await rules();
    const op = body.op;

    if (op === "hello") return answer({ ok: true, rules: e.version });

    if (op === "create" || op === "join") {
      if (body.rules !== e.version) {
        return refuse("rules_mismatch", "This copy of the game uses different rules from the server. Update the game, or publish its rules.", { rules: e.version });
      }
    }

    if (op === "create") {
      const { resp, snapshot } = run(e, { op: "create", seq: 0, seed: seed(), mode: body.mode, player: body.player, ai: body.ai }, null);
      if (!resp.ok) return answer(resp);
      const retired = await admin.rpc("match_retire", { p_user: user });
      if (retired.error) throw new Error(retired.error.message);
      for (let attempt = 0; attempt < 5; attempt++) {
        const code = body.mode === "duel" ? roomCode() : null;
        const inserted = await admin.from("matches").insert({
          code, mode: body.mode, status: resp.store.status, host: user, seq: resp.store.seq, rules: e.version,
          config: resp.store.config, snapshot, pending: null, views: resp.store.views,
          log: resp.log, log_count: resp.log.length,
        }).select("id").single();
        if (!inserted.error) return answer({ ...resp.reply, ok: true, match: inserted.data.id, code, seat: 1, log_from: 0 });
        if (inserted.error.code !== "23505") throw new Error(inserted.error.message); // 23505: the room code is taken
      }
      throw new Error("Could not allocate a room code.");
    }

    if (op === "join") {
      const code = typeof body.code === "string" ? body.code.toUpperCase().replace(/\s/g, "") : "";
      if (!/^[A-Z0-9]{6}$/.test(code)) return refuse("room_not_found", "No open room has that code.");
      const found = await admin.from("matches").select(COLUMNS).eq("code", code).eq("mode", "duel").maybeSingle();
      if (found.error) throw new Error(found.error.message);
      const m = found.data;
      if (!m) return refuse("room_not_found", "No open room has that code.");
      if (m.status !== "waiting") return refuse("room_full", "That room already has two players.");
      if (m.host === user) return refuse("own_room", "You cannot join your own room.");
      if (m.rules !== e.version) return refuse("rules_mismatch", "That room was opened with different rules. Ask the host to open a new one.", { rules: e.version });
      const { resp, snapshot } = run(e, { op: "join", seq: m.seq, seed: seed(), config: m.config, player: body.player }, null);
      if (!resp.ok) return answer(resp);
      const retired = await admin.rpc("match_retire", { p_user: user, p_keep: m.id });
      if (retired.error) throw new Error(retired.error.message);
      const applied = await admin.rpc("match_apply", {
        p_id: m.id, p_seq: m.seq, p_status: resp.store.status, p_pending: null, p_views: resp.store.views,
        p_snapshot: snapshot, p_log: resp.log, p_action: null, p_guest: user, p_config: resp.store.config,
      });
      if (applied.error) throw new Error(applied.error.message);
      if (!applied.data) return refuse("room_full", "That room already has two players.");
      return answer({ ...resp.reply, ok: true, match: m.id, seat: 2, log_from: 0 });
    }

    if (op !== "act" && op !== "leave") return refuse("bad_request", "Unknown operation.");
    if (typeof body.match !== "string" || !/^[0-9a-f-]{36}$/i.test(body.match)) return refuse("not_found", "Match not found.");
    const found = await admin.from("matches").select(COLUMNS).eq("id", body.match).maybeSingle();
    if (found.error) throw new Error(found.error.message);
    const m = found.data;
    const seat = m ? (m.host === user ? 1 : m.guest === user ? 2 : 0) : 0;
    if (!m || !seat) return refuse("not_found", "Match not found.");

    if (op === "leave") {
      if (m.status === "waiting") {
        const gone = await admin.from("matches").delete().eq("id", m.id).eq("status", "waiting");
        if (gone.error) throw new Error(gone.error.message);
      } else if (m.status === "active") {
        const left = await admin.from("matches")
          .update({ status: "abandoned", left_seat: seat, seq: m.seq + 1, updated_at: new Date().toISOString() })
          .eq("id", m.id).eq("status", "active");
        if (left.error) throw new Error(left.error.message);
      }
      return answer({ ok: true });
    }

    // op === "act"
    if (m.status !== "active") return refuse("not_active", "This match is not in progress.", { status: m.status });
    if (typeof body.id === "string" && m.last_action && m.last_action.id === body.id && m.last_action.seat === seat) {
      return answer({ ok: true, duplicate: true, seq: m.seq }); // a retry of a move that did arrive
    }
    if (body.seq !== m.seq) return refuse("stale", "The match has moved on.", { seq: m.seq });
    if (m.rules !== e.version) return refuse("rules_mismatch", "The game rules were updated during this match. Start a new one.", { rules: e.version });
    const { resp, snapshot } = run(e, { op: "act", seq: m.seq, seat, config: m.config, pending: m.pending ?? false, action: body.action }, m.snapshot);
    if (!resp.ok) return answer(resp);
    const applied = await admin.rpc("match_apply", {
      p_id: m.id, p_seq: m.seq, p_status: resp.store.status, p_pending: resp.store.pending || null,
      p_views: resp.store.views, p_snapshot: snapshot, p_log: resp.log,
      p_action: typeof body.id === "string" ? { id: body.id.slice(0, 80), seat } : null,
    });
    if (applied.error) throw new Error(applied.error.message);
    if (!applied.data) return refuse("conflict", "Another request changed the match first.");
    return answer({ ...resp.reply, ok: true, log_from: m.log_count });
  } catch (error) {
    console.error(error);
    return answer({ message: error instanceof Error ? error.message : String(error) }, 500);
  }
});
