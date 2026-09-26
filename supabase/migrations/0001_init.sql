-- Phase 4 cloud schema for a new database.
-- The app ships only the anon key. Row security is forced, so that key
-- cannot read or write another person's rows.

create schema if not exists private;

revoke all on schema private from public;
grant usage on schema private to authenticated, service_role;

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

create table public.notebooks (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name text not null,
  ink_color bigint not null,
  version integer not null default 1,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  deleted_at timestamptz,
  constraint notebooks_name_length check (char_length(name) between 1 and 200),
  constraint notebooks_version_positive check (version >= 1),
  constraint notebooks_id_user_id_key unique (id, user_id)
);

create table public.pages (
  id uuid primary key,
  notebook_id uuid not null,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  page_index integer not null,
  version integer not null default 1,
  captured_at timestamptz not null default pg_catalog.now(),
  paper_rect jsonb not null,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  deleted_at timestamptz,
  constraint pages_page_index_positive check (page_index >= 1),
  constraint pages_version_positive check (version >= 1),
  constraint pages_paper_rect_object check (jsonb_typeof(paper_rect) = 'object'),
  constraint pages_id_user_id_key unique (id, user_id),
  constraint pages_notebook_user_fkey
    foreign key (notebook_id, user_id)
    references public.notebooks (id, user_id)
    on delete cascade
);

create table public.strokes (
  id uuid primary key,
  page_id uuid not null,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  -- 16 bytes per point (float32 x, float32 y, uint16 pressure, uint16 flags,
  -- uint32 dt). 320000 bytes is 20,000 points.
  points bytea not null,
  time_origin_ms bigint not null default 0,
  color bigint not null,
  width double precision not null,
  version integer not null default 1,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  deleted_at timestamptz,
  constraint strokes_points_size check (octet_length(points) <= 320000),
  constraint strokes_version_positive check (version >= 1),
  constraint strokes_width_range check (width > 0 and width < 50),
  constraint strokes_page_user_fkey
    foreign key (page_id, user_id)
    references public.pages (id, user_id)
    on delete cascade
);

create table public.page_text (
  page_id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  text text not null default '',
  tsv tsvector generated always as (to_tsvector('english', text)) stored,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  deleted_at timestamptz,
  constraint page_text_page_user_fkey
    foreign key (page_id, user_id)
    references public.pages (id, user_id)
    on delete cascade
);

create index notebooks_user_updated_idx on public.notebooks (user_id, updated_at);
create index pages_user_updated_idx on public.pages (user_id, updated_at);
create index pages_notebook_id_idx on public.pages (notebook_id);
create index strokes_user_updated_idx on public.strokes (user_id, updated_at);
create index strokes_page_id_idx on public.strokes (page_id);
create index page_text_user_updated_idx on public.page_text (user_id, updated_at);
create index page_text_tsv_idx on public.page_text using gin (tsv);

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
