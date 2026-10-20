-- Keep the Community rank and displayed weekly total on the same
-- deduplicated interval calculation used by StudyUp's local progress math.
-- Existing current-week sessions are eligible regardless of when the
-- friendship was created; friendship controls access, not session age.
-- Apply after 20261113_community_progress_realtime.sql.

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
  clipped_segments as (
    select s.user_id,
           greatest((el ->> 's')::timestamptz, p_start) as start_at,
           least((el ->> 'e')::timestamptz, p_end) as end_at
    from public.study_sessions s
    cross join jsonb_array_elements(
      case when jsonb_typeof(s.segments) = 'array' then s.segments else '[]'::jsonb end
    ) el
    where s.user_id in (select id from eligible)
      and (el ->> 'e')::timestamptz > p_start
      and (el ->> 's')::timestamptz < p_end
  ),
  ordered_segments as (
    select user_id, start_at, end_at,
           max(end_at) over (
             partition by user_id
             order by start_at, end_at
             rows between unbounded preceding and 1 preceding
           ) as prior_end
    from clipped_segments
    where end_at > start_at
  ),
  marked_segments as (
    select user_id, start_at, end_at,
           sum(
             case when prior_end is null or start_at > prior_end then 1 else 0 end
           ) over (
             partition by user_id
             order by start_at, end_at
             rows between unbounded preceding and current row
           ) as island
    from ordered_segments
  ),
  merged_segments as (
    select user_id, island, min(start_at) as start_at, max(end_at) as end_at
    from marked_segments
    group by user_id, island
  ),
  week as (
    select user_id,
           sum(floor(extract(epoch from (end_at - start_at))))::bigint as week_seconds
    from merged_segments
    group by user_id
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
