-- Bring an existing PaperSync database up to the Phase 4 rules.
-- Safe to run again, and safe after 0001_init.sql.

alter table public.notebooks add column if not exists version integer not null default 1;
alter table public.pages add column if not exists version integer not null default 1;
alter table public.pages add column if not exists created_at timestamptz not null default pg_catalog.now();
alter table public.page_text add column if not exists created_at timestamptz not null default pg_catalog.now();
alter table public.page_text add column if not exists deleted_at timestamptz;
alter table public.strokes add column if not exists time_origin_ms bigint not null default 0;

alter table public.notebooks alter column user_id set default auth.uid();
alter table public.pages alter column user_id set default auth.uid();
alter table public.strokes alter column user_id set default auth.uid();
alter table public.page_text alter column user_id set default auth.uid();

do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'strokes'
      and column_name = 'points'
      and udt_name = 'jsonb'
  ) then
    alter table public.strokes drop constraint if exists strokes_points_array;
    alter table public.strokes drop column points;
    alter table public.strokes add column points bytea not null;
  end if;
end $$;

alter table public.notebooks drop constraint if exists notebooks_name_not_blank;
alter table public.notebooks drop constraint if exists notebooks_name_length;
alter table public.notebooks add constraint notebooks_name_length
  check (char_length(name) between 1 and 200);

alter table public.notebooks drop constraint if exists notebooks_version_positive;
alter table public.notebooks add constraint notebooks_version_positive check (version >= 1);

alter table public.pages drop constraint if exists pages_page_index_nonnegative;
alter table public.pages drop constraint if exists pages_page_index_positive;
alter table public.pages add constraint pages_page_index_positive check (page_index >= 1);

alter table public.pages drop constraint if exists pages_version_positive;
alter table public.pages add constraint pages_version_positive check (version >= 1);

alter table public.strokes drop constraint if exists strokes_width_positive;
alter table public.strokes drop constraint if exists strokes_width_range;
alter table public.strokes add constraint strokes_width_range check (width > 0 and width < 50);

alter table public.strokes drop constraint if exists strokes_points_size;
alter table public.strokes add constraint strokes_points_size
  check (octet_length(points) <= 320000);

create or replace function private.touch_row()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  if tg_op = 'UPDATE' then
    if new.user_id is distinct from old.user_id then
      raise exception 'user_id cannot change';
    end if;
    if tg_table_name in ('notebooks', 'pages', 'strokes')
      and new.version < old.version then
      raise exception 'version cannot decrease';
    end if;
  end if;
  new.updated_at := pg_catalog.now();
  return new;
end;
$$;

revoke all on function private.touch_row() from public, anon;
grant execute on function private.touch_row() to authenticated, service_role;

drop trigger if exists notebooks_set_updated_at on public.notebooks;
drop trigger if exists pages_set_updated_at on public.pages;
drop trigger if exists strokes_set_updated_at on public.strokes;
drop trigger if exists page_text_set_updated_at on public.page_text;
drop trigger if exists notebooks_touch on public.notebooks;
drop trigger if exists pages_touch on public.pages;
drop trigger if exists strokes_touch on public.strokes;
drop trigger if exists page_text_touch on public.page_text;

create trigger notebooks_touch
  before insert or update on public.notebooks
  for each row execute function private.touch_row();
create trigger pages_touch
  before insert or update on public.pages
  for each row execute function private.touch_row();
create trigger strokes_touch
  before insert or update on public.strokes
  for each row execute function private.touch_row();
create trigger page_text_touch
  before insert or update on public.page_text
  for each row execute function private.touch_row();

alter table public.notebooks enable row level security;
alter table public.pages enable row level security;
alter table public.strokes enable row level security;
alter table public.page_text enable row level security;
alter table public.notebooks force row level security;
alter table public.pages force row level security;
alter table public.strokes force row level security;
alter table public.page_text force row level security;

revoke all on table public.notebooks from anon, authenticated, public;
revoke all on table public.pages from anon, authenticated, public;
revoke all on table public.strokes from anon, authenticated, public;
revoke all on table public.page_text from anon, authenticated, public;

grant select, insert, update, delete on table public.notebooks to authenticated, service_role;
grant select, insert, update, delete on table public.pages to authenticated, service_role;
grant select, insert, update, delete on table public.strokes to authenticated, service_role;
grant select, insert, update, delete on table public.page_text to authenticated, service_role;

drop policy if exists notebooks_owner on public.notebooks;
drop policy if exists pages_owner on public.pages;
drop policy if exists strokes_owner on public.strokes;
drop policy if exists page_text_owner on public.page_text;

drop policy if exists notebooks_select on public.notebooks;
drop policy if exists notebooks_insert on public.notebooks;
drop policy if exists notebooks_update on public.notebooks;
drop policy if exists notebooks_delete on public.notebooks;
drop policy if exists pages_select on public.pages;
drop policy if exists pages_insert on public.pages;
drop policy if exists pages_update on public.pages;
drop policy if exists pages_delete on public.pages;
drop policy if exists strokes_select on public.strokes;
drop policy if exists strokes_insert on public.strokes;
drop policy if exists strokes_update on public.strokes;
drop policy if exists strokes_delete on public.strokes;
drop policy if exists page_text_select on public.page_text;
drop policy if exists page_text_insert on public.page_text;
drop policy if exists page_text_update on public.page_text;
drop policy if exists page_text_delete on public.page_text;

create policy notebooks_select on public.notebooks
  for select to authenticated
  using ((select auth.uid()) = user_id);
create policy notebooks_insert on public.notebooks
  for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy notebooks_update on public.notebooks
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy notebooks_delete on public.notebooks
  for delete to authenticated
  using ((select auth.uid()) = user_id);

create policy pages_select on public.pages
  for select to authenticated
  using (
    (select auth.uid()) = user_id
    and exists (
      select 1 from public.notebooks n
      where n.id = notebook_id and n.user_id = (select auth.uid())
    )
  );
create policy pages_insert on public.pages
  for insert to authenticated
  with check (
    (select auth.uid()) = user_id
    and exists (
      select 1 from public.notebooks n
      where n.id = notebook_id and n.user_id = (select auth.uid())
    )
  );
create policy pages_update on public.pages
  for update to authenticated
  using (
    (select auth.uid()) = user_id
    and exists (
      select 1 from public.notebooks n
      where n.id = notebook_id and n.user_id = (select auth.uid())
    )
  )
  with check (
    (select auth.uid()) = user_id
    and exists (
      select 1 from public.notebooks n
      where n.id = notebook_id and n.user_id = (select auth.uid())
    )
  );
create policy pages_delete on public.pages
  for delete to authenticated
  using (
    (select auth.uid()) = user_id
    and exists (
      select 1 from public.notebooks n
      where n.id = notebook_id and n.user_id = (select auth.uid())
    )
  );

create policy strokes_select on public.strokes
  for select to authenticated
  using (
    (select auth.uid()) = user_id
    and exists (
      select 1 from public.pages p
      where p.id = page_id and p.user_id = (select auth.uid())
    )
  );
create policy strokes_insert on public.strokes
  for insert to authenticated
  with check (
    (select auth.uid()) = user_id
    and exists (
      select 1 from public.pages p
      where p.id = page_id and p.user_id = (select auth.uid())
    )
  );
create policy strokes_update on public.strokes
  for update to authenticated
  using (
    (select auth.uid()) = user_id
    and exists (
      select 1 from public.pages p
      where p.id = page_id and p.user_id = (select auth.uid())
    )
  )
  with check (
    (select auth.uid()) = user_id
    and exists (
      select 1 from public.pages p
      where p.id = page_id and p.user_id = (select auth.uid())
    )
  );
create policy strokes_delete on public.strokes
  for delete to authenticated
  using (
    (select auth.uid()) = user_id
    and exists (
      select 1 from public.pages p
      where p.id = page_id and p.user_id = (select auth.uid())
    )
  );

create policy page_text_select on public.page_text
  for select to authenticated
  using (
    (select auth.uid()) = user_id
    and exists (
      select 1 from public.pages p
      where p.id = page_id and p.user_id = (select auth.uid())
    )
  );
create policy page_text_insert on public.page_text
  for insert to authenticated
  with check (
    (select auth.uid()) = user_id
    and exists (
      select 1 from public.pages p
      where p.id = page_id and p.user_id = (select auth.uid())
    )
  );
create policy page_text_update on public.page_text
  for update to authenticated
  using (
    (select auth.uid()) = user_id
    and exists (
      select 1 from public.pages p
      where p.id = page_id and p.user_id = (select auth.uid())
    )
  )
  with check (
    (select auth.uid()) = user_id
    and exists (
      select 1 from public.pages p
      where p.id = page_id and p.user_id = (select auth.uid())
    )
  );
create policy page_text_delete on public.page_text
  for delete to authenticated
  using (
    (select auth.uid()) = user_id
    and exists (
      select 1 from public.pages p
      where p.id = page_id and p.user_id = (select auth.uid())
    )
  );

create index if not exists notebooks_user_updated_idx
  on public.notebooks (user_id, updated_at);
create index if not exists pages_user_updated_idx
  on public.pages (user_id, updated_at);
create index if not exists strokes_user_updated_idx
  on public.strokes (user_id, updated_at);
create index if not exists page_text_user_updated_idx
  on public.page_text (user_id, updated_at);
-- notebook_id and page_id are already the leading columns of the composite
-- foreign-key indexes from the first schema. A second index would be unused.
