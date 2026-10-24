-- Persist which account accepted an invite so a retry after a lost response
-- is safe without allowing a different account to reuse a single-use code.
-- Keep this private: clients can only use the preview/accept RPCs.

create table if not exists public.invitation_acceptances (
  invitation_id uuid not null
    references public.invitations (id) on delete cascade,
  accepted_by uuid not null
    references auth.users (id) on delete cascade,
  accepted_at timestamptz not null default now(),
  primary key (invitation_id, accepted_by)
);

alter table public.invitation_acceptances enable row level security;
revoke all on table public.invitation_acceptances from public, anon, authenticated;

create or replace function public.accept_invitation(p_token text)
returns table (friend_id uuid, display_name text)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_hash text;
  v_inv record;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if p_token is null or length(p_token) < 16 then
    raise exception 'invalid token' using errcode = '22000';
  end if;
  v_hash := encode(digest(p_token, 'sha256'), 'hex');

  select * into v_inv
  from public.invitations
  where token_hash = v_hash
  for update;

  if not found then
    raise exception 'invalid token' using errcode = '22000';
  end if;
  if v_inv.created_by = auth.uid() then
    raise exception 'self invite' using errcode = '22000';
  end if;

  if exists (
    select 1
    from public.invitation_acceptances a
    where a.invitation_id = v_inv.id
      and a.accepted_by = auth.uid()
  ) then
    if public.community_are_friends(auth.uid(), v_inv.created_by) then
      return query
        select p.id, p.display_name
        from public.community_profiles p
        where p.id = v_inv.created_by;
      return;
    end if;
    raise exception 'invitation already accepted' using errcode = '22000';
  end if;

  if v_inv.status = 'revoked' then
    raise exception 'revoked' using errcode = '22000';
  end if;
  if v_inv.expires_at <= now() then
    update public.invitations set status = 'expired' where id = v_inv.id;
    raise exception 'expired' using errcode = '22000';
  end if;
  if v_inv.status <> 'active' or v_inv.uses >= v_inv.max_uses then
    raise exception 'already accepted' using errcode = '22000';
  end if;
  if public.community_are_friends(auth.uid(), v_inv.created_by) then
    raise exception 'already friends' using errcode = '22000';
  end if;
  if exists (
    select 1
    from public.friend_requests r
    where r.status = 'pending'
      and (
        (r.from_id = auth.uid() and r.to_id = v_inv.created_by)
        or (r.from_id = v_inv.created_by and r.to_id = auth.uid())
      )
  ) then
    raise exception 'request pending' using errcode = '22000';
  end if;

  insert into public.friendships (user_low, user_high)
  values (
    least(auth.uid(), v_inv.created_by),
    greatest(auth.uid(), v_inv.created_by)
  )
  on conflict do nothing;

  insert into public.invitation_acceptances (invitation_id, accepted_by)
  values (v_inv.id, auth.uid())
  on conflict do nothing;

  update public.invitations
  set uses = uses + 1,
      status = case
        when uses + 1 >= max_uses then 'accepted'::text
        else 'active'::text
      end
  where id = v_inv.id;

  update public.friend_requests
  set status = 'cancelled'
  where status = 'pending'
    and (
      (from_id = auth.uid() and to_id = v_inv.created_by)
      or (from_id = v_inv.created_by and to_id = auth.uid())
    );

  return query
    select p.id, p.display_name
    from public.community_profiles p
    where p.id = v_inv.created_by;
end;
$$;

revoke all on function public.accept_invitation(text) from public, anon;
grant execute on function public.accept_invitation(text) to authenticated;
