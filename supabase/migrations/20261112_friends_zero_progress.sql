-- Friends with no study data in the queried week must still appear.
--
-- Root cause of "my friend accepted my invitation but never shows up in
-- Community": leaderboard_scope('friends', ...) filtered members with
--   and (p.id = auth.uid() or coalesce(w.week_seconds, 0) > 0 or p_scope = 'everyone')
-- so an accepted friend who has not studied in that window (zero study
-- time, zero XP — the normal state right after accepting) returned no row
-- at all. The app could not show them: there was no profile, no name, no
-- avatar.
--
-- Friendship is membership, not progress. The friends scope now returns
-- EVERY accepted, opted-in friend; the client decides how a member with no
-- shared data is displayed (unranked, honest zeros) and still ranks by real
-- seconds when data arrives. Nothing else changes:
--   - only SUMs/aggregates leave the database (unchanged);
--   - eligibility is still friends + leaderboard_opt_in (unchanged);
--   - the 'everyone' scope is unchanged;
--   - the user is never opted in without their own flag.
--
-- Run AFTER 20261102_social_backend.sql and 20261104_hardening_fix.sql.
-- Safe to re-run (plain CREATE OR REPLACE).

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
  if p_scope <> 'friends' and p_scope <> 'everyone' then
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
    where p.leaderboard_opt_in
      and (
        p_scope = 'everyone'
        or public.community_are_friends(auth.uid(), p.id)
        or p.id = auth.uid()
      )
  ),
  -- Exact overlap seconds from validated segments. This definer function
  -- may read segments rows, but only SUMS leave the database.
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
  -- Current streak per StudyUp definition: consecutive studied days
  -- counting back from today (quiet today allowed when yesterday was
  -- studied). Computed here so every client shows the same value.
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
         coalesce(w.week_seconds, 0), coalesce(wd.active_days, 0),
         coalesce(t.total_seconds, 0), coalesce(s.streak_days, 0)
  from public.community_profiles p
  left join week w on w.user_id = p.id
  left join wdays wd on wd.user_id = p.id
  left join totals t on t.user_id = p.id
  left join streak s on s.user_id = p.id
  -- Every eligible member is returned; a member with no rows in this week
  -- simply carries zero aggregates. Clients list them unranked instead of
  -- hiding a real friend.
  where p.id in (select id from eligible)
  order by coalesce(w.week_seconds, 0) desc, p.display_name
  limit 100;
end;
$$;

revoke all on function public.leaderboard_scope(text, timestamptz, timestamptz) from public;
grant execute on function public.leaderboard_scope(text, timestamptz, timestamptz) to authenticated;