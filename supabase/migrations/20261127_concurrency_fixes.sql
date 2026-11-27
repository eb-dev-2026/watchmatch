begin;

-- 1) One swipe per user per title, one match per title
alter table swipes drop constraint if exists swipes_one_per_user_media;
alter table swipes add constraint swipes_one_per_user_media
  unique (room_id, user_id, media_id, media_type);

alter table matches drop constraint if exists matches_one_per_media;
alter table matches add constraint matches_one_per_media
  unique (room_id, media_id, media_type);

create or replace function join_room(p_code text, p_user_id text)
returns rooms language plpgsql as $$
declare r rooms;
begin
    select * into r from rooms where code = p_code for update;
    if not found then raise exception 'ROOM_NOT_FOUND'; end if;
    if p_user_id in (r.host_id, r.guest_id) then return r; end if;
    if r.guest_id is not null then raise exception 'ROOM_FULL'; end if;
    update rooms set guest_id = p_user_id, status = 'active'
    where id = r.id returning * into r;
    return r;
end $$;

-- 3) Swipe and match under the same lock
create or replace function swipe_and_match(p_room_id uuid, p_user_id text,
  p_media_id integer, p_media_type text, p_direction text)
returns boolean language plpgsql as $$
declare r rooms; v_other text;
begin
  select * into r from rooms where id = p_room_id for update;
  if not found then raise exception 'ROOM_NOT_FOUND'; end if;
  if p_user_id is distinct from r.host_id
     and p_user_id is distinct from r.guest_id then
    raise exception 'NOT_A_MEMBER';
  end if;

  insert into swipes (room_id, user_id, media_id, media_type, direction)
  values (p_room_id, p_user_id, p_media_id, p_media_type, p_direction)
  on conflict do nothing;
  if not found or p_direction <> 'like' or r.guest_id is null then
    return false;
  end if;

  v_other := case when p_user_id = r.host_id then r.guest_id else r.host_id end;
  if not exists (select 1 from swipes where room_id = p_room_id
      and user_id = v_other and media_id = p_media_id
      and media_type = p_media_type and direction = 'like') then
    return false;
  end if;

  insert into matches (room_id, user1_id, user2_id, media_id, media_type)
  values (p_room_id, p_user_id, v_other, p_media_id, p_media_type)
  on conflict do nothing;
  return true;
end $$;

grant execute on function join_room(text, text) to anon, authenticated;
grant execute on function swipe_and_match(uuid, text, integer, text, text)
  to anon, authenticated;
notify pgrst, 'reload schema';

commit;
