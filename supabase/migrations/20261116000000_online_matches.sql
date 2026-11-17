-- Tide & Timber online play.
--
-- Clients never read or write these tables. Row Level Security is enabled with no policies,
-- so the anon and authenticated roles see nothing; the "game" Edge Function works with the
-- service role, and players reach their own match only through match_state(), which hands a
-- seat nothing but that seat's view. Nothing here is published to Realtime.

create table if not exists public.matches (
  id          uuid primary key default gen_random_uuid(),
  code        text,                               -- room code (two-player matches)
  mode        text not null check (mode in ('solo','duel')),
  status      text not null default 'waiting' check (status in ('waiting','active','finished','abandoned')),
  host        uuid not null references auth.users (id) on delete cascade,   -- seat 1
  guest       uuid references auth.users (id) on delete set null,           -- seat 2
  left_seat   smallint,                           -- who left an abandoned match
  seq         integer not null default 0,         -- bumped on every change; guards against double moves
  rules       text not null,                      -- rules version the match is played with
  config      jsonb not null,                     -- factions and both deck lists (private)
  snapshot    text,                               -- battle state incl. hands, deck order, RNG (private)
  pending     jsonb,                              -- inputs since the snapshot while a choice is open (private)
  views       jsonb not null default '{}'::jsonb, -- {"1": seat 1's view, "2": seat 2's view}
  log         jsonb not null default '[]'::jsonb, -- battle record; public to both players
  log_count   integer not null default 0,
  last_action jsonb,                              -- {id, seat} of the last applied input (retries)
  host_seen   timestamptz,
  guest_seen  timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create unique index if not exists matches_code_key on public.matches (code) where code is not null;
create index if not exists matches_host_idx on public.matches (host);
create index if not exists matches_guest_idx on public.matches (guest);
create index if not exists matches_updated_idx on public.matches (updated_at);

-- The game rules (Lua source) the Edge Function runs. Uploaded by scripts/publish_rules.py.
create table if not exists public.rules (
  version      text primary key,
  modules      jsonb not null,                    -- {"battle": "<lua source>", ...}
  published_at timestamptz not null default now()
);
-- SHA-256 digests of the secrets allowed to publish rules. The secret itself stays on the
-- developer's machine (supabase/.publish_secret).
create table if not exists public.deploy_keys (
  digest     text primary key,
  created_at timestamptz not null default now()
);

alter table public.matches enable row level security;
alter table public.rules enable row level security;
alter table public.deploy_keys enable row level security;
revoke all on public.matches, public.rules, public.deploy_keys from anon, authenticated;

-- Polling. Returns only {seq, status} while nothing changed since p_seq; otherwise also the
-- caller's own view and the record lines after the first p_log.
create or replace function public.match_state(p_match uuid, p_seq integer default -1, p_log integer default 0)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  m public.matches;
  me uuid := auth.uid();
  seat integer;
  other_seen timestamptz;
  result jsonb;
begin
  if me is null then return jsonb_build_object('error', 'not_found'); end if;
  select * into m from public.matches where id = p_match;
  if not found then return jsonb_build_object('error', 'not_found'); end if;
  if m.host = me then seat := 1; other_seen := m.guest_seen;
  elsif m.guest = me then seat := 2; other_seen := m.host_seen;
  else return jsonb_build_object('error', 'not_found');
  end if;
  -- Presence, written at most every 10 seconds per player.
  if seat = 1 and (m.host_seen is null or m.host_seen < now() - interval '10 seconds') then
    update public.matches set host_seen = now() where id = m.id;
  elsif seat = 2 and (m.guest_seen is null or m.guest_seen < now() - interval '10 seconds') then
    update public.matches set guest_seen = now() where id = m.id;
  end if;
  result := jsonb_build_object('seq', m.seq, 'status', m.status, 'seat', seat, 'code', m.code,
    'left', m.left_seat,
    'opponent_seen', case when other_seen is null then null else floor(extract(epoch from now() - other_seen)) end);
  if m.seq is distinct from p_seq then
    result := result || jsonb_build_object(
      'view', m.views -> (seat::text),
      'log_from', least(greatest(p_log, 0), m.log_count),
      'log', jsonb_path_query_array(m.log, '$[$from to last]',
               jsonb_build_object('from', least(greatest(p_log, 0), m.log_count))));
  end if;
  return jsonb_strip_nulls(result);
end;
$$;
revoke all on function public.match_state(uuid, integer, integer) from public, anon;
grant execute on function public.match_state(uuid, integer, integer) to authenticated;

-- Applies one accepted input. The "where seq = p_seq" makes concurrent or repeated requests
-- lose: only the first one finds the row at the sequence number it read.
create or replace function public.match_apply(
  p_id uuid, p_seq integer, p_status text, p_pending jsonb, p_views jsonb,
  p_snapshot text, p_log jsonb, p_action jsonb,
  p_guest uuid default null, p_config jsonb default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.matches set
    status = p_status,
    pending = p_pending,
    views = p_views,
    snapshot = coalesce(p_snapshot, snapshot),
    log = log || coalesce(p_log, '[]'::jsonb),
    log_count = log_count + jsonb_array_length(coalesce(p_log, '[]'::jsonb)),
    last_action = p_action,
    guest = coalesce(p_guest, guest),
    config = coalesce(p_config, config),
    seq = p_seq + 1,
    updated_at = now()
  where id = p_id and seq = p_seq and (p_guest is null or guest is null);
  return found;
end;
$$;
revoke all on function public.match_apply(uuid, integer, text, jsonb, jsonb, text, jsonb, jsonb, uuid, jsonb) from public, anon, authenticated;
grant execute on function public.match_apply(uuid, integer, text, jsonb, jsonb, text, jsonb, jsonb, uuid, jsonb) to service_role;

-- A player is in one match at a time: starting or joining another closes the earlier ones.
-- Also removes matches nobody has touched for a week and rooms nobody joined.
create or replace function public.match_retire(p_user uuid, p_keep uuid default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.matches
   where status = 'waiting' and host = p_user and id is distinct from p_keep;
  update public.matches
     set status = 'abandoned', left_seat = case when host = p_user then 1 else 2 end,
         seq = seq + 1, updated_at = now()
   where status = 'active' and (host = p_user or guest = p_user) and id is distinct from p_keep;
  delete from public.matches
   where updated_at < now() - interval '7 days'
      or (status = 'waiting' and created_at < now() - interval '6 hours');
end;
$$;
revoke all on function public.match_retire(uuid, uuid) from public, anon, authenticated;
grant execute on function public.match_retire(uuid, uuid) to service_role;

-- Uploads a new rules version. Open to the anon role, but useless without the publish secret.
create or replace function public.publish_rules(p_secret text, p_version text, p_modules jsonb)
returns text
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_secret is null or length(p_secret) < 32 or not exists (
       select 1 from public.deploy_keys
        where digest = encode(sha256(convert_to(p_secret, 'UTF8')), 'hex')) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if p_version !~ '^[0-9a-f]{16}$' or jsonb_typeof(p_modules) <> 'object'
     or not (p_modules ? 'online.server') or octet_length(p_modules::text) > 2000000 then
    raise exception 'malformed rules bundle' using errcode = '22023';
  end if;
  insert into public.rules (version, modules) values (p_version, p_modules)
    on conflict (version) do update set modules = excluded.modules, published_at = now();
  delete from public.rules
   where version not in (select version from public.rules order by published_at desc limit 3);
  return p_version;
end;
$$;
revoke all on function public.publish_rules(text, text, jsonb) from public;
grant execute on function public.publish_rules(text, text, jsonb) to anon, authenticated;
