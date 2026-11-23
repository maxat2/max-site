-- «Макс за компом без перерыва» — одна строка со статистикой
create table if not exists public.max_streak (
  id          int primary key default 1 check (id = 1),
  last_break  timestamptz not null default now(),
  record_ms   bigint      not null default 0,
  breaks      int         not null default 0
);
insert into public.max_streak (id) values (1) on conflict do nothing;

-- прямой доступ к таблице закрыт: RLS включён, политик нет
alter table public.max_streak enable row level security;

-- прочитать статистику (+ текущее время сервера, чтобы таймер шёл точно)
create or replace function public.get_streak()
returns json language sql security definer set search_path = public as $$
  select json_build_object('last_break', last_break, 'record_ms', record_ms, 'breaks', breaks, 'now', now())
  from public.max_streak where id = 1;
$$;

-- гость сделал первый ход: серия прерывается, время ставит сервер
create or replace function public.break_streak()
returns json language plpgsql security definer set search_path = public as $$
declare r public.max_streak; cur bigint;
begin
  select * into r from public.max_streak where id = 1 for update;
  -- защита от накрутки: не чаще раза в 10 секунд
  if now() - r.last_break >= interval '10 seconds' then
    cur := (extract(epoch from now() - r.last_break) * 1000)::bigint;
    update public.max_streak
       set record_ms = greatest(record_ms, cur), breaks = breaks + 1, last_break = now()
     where id = 1 returning * into r;
  end if;
  return json_build_object('last_break', r.last_break, 'record_ms', r.record_ms, 'breaks', r.breaks, 'now', now());
end $$;

revoke all on function public.get_streak(), public.break_streak() from public;
grant execute on function public.get_streak(), public.break_streak() to anon;
