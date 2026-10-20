-- Send a metadata-only realtime invalidation after shared session-day
-- aggregates change. Raw study_sessions and session_days stay unpublished.
-- Apply after 20261112_friends_zero_progress.sql.

-- The leaderboard opt-in is the consent boundary for progress, including
-- reads through RLS and the daily aggregate RPC.
drop policy if exists "friends read day aggregates" on public.session_days;
create policy "friends read day aggregates"
  on public.session_days
  for select
  to authenticated
  using (
    public.community_are_friends(auth.uid(), user_id)
    and exists (
      select 1
      from public.community_profiles p
      where p.id = user_id and p.leaderboard_opt_in
    )
  );

-- No direct table reads for opted-in strangers. Community progress is
-- friends-only; the owner policy above still permits private self access.
drop policy if exists "opted-in public aggregates" on public.session_days;

create or replace function public.daily_rows(
  p_user_id uuid,
  p_from date,
  p_to date
)
returns table (day date, seconds integer)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if p_to < p_from or p_to - p_from > 730 then
    raise exception 'bad range' using errcode = '22000';
  end if;
  if p_user_id <> auth.uid() and (
    not public.community_are_friends(auth.uid(), p_user_id)
    or not exists (
      select 1
      from public.community_profiles p
      where p.id = p_user_id and p.leaderboard_opt_in
    )
  ) then
    raise exception 'not permitted' using errcode = '28000';
  end if;
  return query
  select d.day, d.seconds
  from public.session_days d
  where d.user_id = p_user_id
    and d.day between p_from and p_to
  order by d.day;
end;
$$;

revoke all on function public.daily_rows(uuid, date, date) from public;
grant execute on function public.daily_rows(uuid, date, date) to authenticated;

-- The app exposes a friends-only Community board. Restrict the definer RPC
-- to that scope so opted-in users' aggregates are never visible to strangers.
create or replace function public.leaderboard_scope(
  p_scope text,
  p_start timestamptz,
  p_end timestamptz
)
returns table (
  user_id uuid,
  display_name text,
  avatar_id text,
  blob_variant integer,
  week_seconds bigint,
  active_days bigint,
  total_seconds bigint,
  streak_days integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if p_scope is distinct from 'friends' then
    raise exception 'bad scope' using errcode = '22000';
  end if;
  if p_end <= p_start or p_end - p_start > interval '8 days' then
    raise exception 'bad range' using errcode = '22000';
  end if;
  if p_start < timestamptz '2000-01-01' or p_end > now() + interval '8 days' then
    raise exception 'range out of bounds' using errcode = '22000';
  end if;
  return query
  with eligible as (
    select p.id
    from public.community_profiles p
    where public.community_are_friends(auth.uid(), p.id)
       or p.id = auth.uid()
  ),
  week as (
    select s.user_id,
           coalesce(sum(
             case
               when (el ->> 'e')::timestamptz > p_start
                and (el ->> 's')::timestamptz < p_end
               then extract(epoch from (
                 least((el ->> 'e')::timestamptz, p_end) -
                 greatest((el ->> 's')::timestamptz, p_start)
               ))
               else 0
             end
           ), 0)::bigint as week_seconds
    from public.study_sessions s
    cross join jsonb_array_elements(
      case when jsonb_typeof(s.segments) = 'array' then s.segments else '[]'::jsonb end
    ) el
    where s.user_id in (select id from eligible)
    group by s.user_id
  ),
  wdays as (
    select d.user_id, count(*)::bigint as active_days
    from public.session_days d
    where d.seconds > 0
      and d.day_start_utc < p_end
      and d.day_start_utc + interval '24 hours' > p_start
      and d.user_id in (select id from eligible)
    group by d.user_id
  ),
  totals as (
    select d.user_id, coalesce(sum(d.seconds), 0)::bigint as total_seconds
    from public.session_days d
    where d.user_id in (select id from eligible)
    group by d.user_id
  ),
  streak as (
    select days.user_id, count(*)::int as streak_days
    from (
      select d.user_id, d.day,
             row_number() over (
               partition by d.user_id order by d.day desc
             ) as rn,
             max(d.day) over (partition by d.user_id) as anchor
      from public.session_days d
      where d.seconds > 0
        and d.day <= current_date
        and d.user_id in (select id from eligible)
    ) days
    where anchor >= current_date - 1
      and day = anchor - (rn - 1)::integer
    group by days.user_id
  )
  select p.id, p.display_name, p.avatar_id, p.blob_variant,
         case when p.id = auth.uid() or p.leaderboard_opt_in
              then coalesce(w.week_seconds, 0) else 0 end,
         case when p.id = auth.uid() or p.leaderboard_opt_in
              then coalesce(wd.active_days, 0) else 0 end,
         case when p.id = auth.uid() or p.leaderboard_opt_in
              then coalesce(t.total_seconds, 0) else 0 end,
         case when p.id = auth.uid() or p.leaderboard_opt_in
              then coalesce(s.streak_days, 0) else 0 end
  from public.community_profiles p
  left join week w on w.user_id = p.id
  left join wdays wd on wd.user_id = p.id
  left join totals t on t.user_id = p.id
  left join streak s on s.user_id = p.id
  where p.id in (select id from eligible)
  order by
    case when p.id = auth.uid() or p.leaderboard_opt_in
         then coalesce(w.week_seconds, 0) else 0 end desc,
    p.display_name
  limit 100;
end;
$$;

revoke all on function public.leaderboard_scope(text, timestamptz, timestamptz) from public;
grant execute on function public.leaderboard_scope(text, timestamptz, timestamptz) to authenticated;

create table if not exists public.community_progress_events (
  user_id uuid primary key references auth.users (id) on delete cascade,
  updated_at timestamptz not null default now()
);

alter table public.community_progress_events enable row level security;
revoke all on table public.community_progress_events from public, anon;
grant select on table public.community_progress_events to authenticated;

drop policy if exists "friends read shared progress events"
  on public.community_progress_events;
create policy "friends read shared progress events"
  on public.community_progress_events
  for select
  to authenticated
  using (
    auth.uid() = user_id
    or (
      public.community_are_friends(auth.uid(), user_id)
      and exists (
        select 1
        from public.community_profiles p
        where p.id = user_id and p.leaderboard_opt_in
      )
    )
  );

create or replace function public.record_community_progress_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  changed_user_id uuid;
begin
  if tg_op = 'DELETE' then
    changed_user_id := old.user_id;
  else
    changed_user_id := new.user_id;
  end if;

  insert into public.community_progress_events (user_id, updated_at)
  values (changed_user_id, clock_timestamp())
  on conflict (user_id) do update
    set updated_at = excluded.updated_at;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

drop trigger if exists record_community_progress_change
  on public.session_days;
create trigger record_community_progress_change
  after insert or update or delete on public.session_days
  for each row execute function public.record_community_progress_change();

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'community_progress_events'
  ) then
    alter publication supabase_realtime
      add table public.community_progress_events;
  end if;
end $$;
