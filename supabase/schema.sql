-- Mesa dos Reis: estrutura do banco no Supabase
-- Cole tudo no SQL Editor do seu projeto e clique em Run.

-- Perfis (nome de jogador)
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nick text not null check (char_length(nick) between 3 and 24),
  created_at timestamptz not null default now()
);
create unique index if not exists profiles_nick_unique on public.profiles (lower(nick));

-- Builds (owner nulo = build de exemplo criada pelo dono do site)
create table if not exists public.builds (
  id uuid primary key default gen_random_uuid(),
  owner uuid references public.profiles(id) on delete cascade,
  title text not null check (char_length(title) between 4 and 80),
  king text not null check (king in ('nothing','spells','greed','blood','nature','nomads','stone','progress','time')),
  patch text check (char_length(patch) <= 24),
  summary text check (char_length(summary) <= 140),
  guide text check (char_length(guide) <= 6000),
  perks text[] not null default '{}',
  tags text[] not null default '{}',
  layout jsonb not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.touch_updated_at() returns trigger language plpgsql as $$
begin new.updated_at = now(); new.created_at = old.created_at; new.owner = old.owner; return new; end $$;
drop trigger if exists builds_touch on public.builds;
create trigger builds_touch before update on public.builds for each row execute function public.touch_updated_at();

-- Votos (um por jogador por build)
create table if not exists public.votes (
  build_id uuid not null references public.builds(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  value smallint not null check (value in (-1, 1)),
  created_at timestamptz not null default now(),
  primary key (build_id, user_id)
);

-- Ranking: build + autor + contagem de votos
create or replace view public.builds_ranked with (security_invoker = on) as
select b.*, p.nick as owner_nick,
       coalesce(sum(v.value), 0)::int as score,
       count(v.value) filter (where v.value = 1)::int as up,
       count(v.value) filter (where v.value = -1)::int as down
from public.builds b
left join public.profiles p on p.id = b.owner
left join public.votes v on v.build_id = b.id
group by b.id, p.nick;

-- Regras de acesso (RLS): todo mundo lê; cada jogador só mexe no que é dele
alter table public.profiles enable row level security;
alter table public.builds enable row level security;
alter table public.votes enable row level security;

drop policy if exists "perfis visiveis" on public.profiles;
create policy "perfis visiveis" on public.profiles for select using (true);
drop policy if exists "cria o proprio perfil" on public.profiles;
create policy "cria o proprio perfil" on public.profiles for insert to authenticated with check (id = auth.uid());
drop policy if exists "edita o proprio perfil" on public.profiles;
create policy "edita o proprio perfil" on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

drop policy if exists "builds visiveis" on public.builds;
create policy "builds visiveis" on public.builds for select using (true);
drop policy if exists "publica build propria" on public.builds;
create policy "publica build propria" on public.builds for insert to authenticated with check (owner = auth.uid());
drop policy if exists "edita build propria" on public.builds;
create policy "edita build propria" on public.builds for update to authenticated using (owner = auth.uid()) with check (owner = auth.uid());
drop policy if exists "apaga build propria" on public.builds;
create policy "apaga build propria" on public.builds for delete to authenticated using (owner = auth.uid());

drop policy if exists "votos visiveis" on public.votes;
create policy "votos visiveis" on public.votes for select using (true);
drop policy if exists "vota por si" on public.votes;
create policy "vota por si" on public.votes for insert to authenticated with check (user_id = auth.uid());
drop policy if exists "muda o proprio voto" on public.votes;
create policy "muda o proprio voto" on public.votes for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists "remove o proprio voto" on public.votes;
create policy "remove o proprio voto" on public.votes for delete to authenticated using (user_id = auth.uid());

-- Permissões da API (necessárias se "Automatically expose new tables" estiver desligado)
grant usage on schema public to anon, authenticated;
grant select on public.profiles, public.builds, public.votes, public.builds_ranked to anon, authenticated;
grant insert, update on public.profiles to authenticated;
grant insert, update, delete on public.builds, public.votes to authenticated;

-- Builds de exemplo (apague quando quiser: delete from public.builds where owner is null;)
insert into public.builds (owner, title, king, summary, guide, perks, tags, layout)
select * from (values
 (null::uuid, 'Linha de frente de Soldados com Blacksmith', 'nothing',
  'Exemplo: soldados em volta do Castle, com Steel Coat acumulado no Soldier da frente.',
  E'Build de exemplo para mostrar como a página funciona. Substitua pelas suas.\n\nComece fechando a frente do Castle com Soldier e Archer, e use Farm para bancar a expansão.\n\nConcentre as camadas de Steel Coat no Soldier da frente, que é quem segura a horda.',
  array['Protector','Valiant'], array['Iniciante','Defensiva'],
  '[null,null,null,null,null,null,{"card":"Archer","lv":2,"ench":[]},{"card":"Soldier","lv":3,"ench":[{"card":"Steel Coat","n":3}]},{"card":"Archer","lv":2,"ench":[]},null,null,{"card":"Blacksmith","lv":1,"ench":[]},{"card":"Castle","lv":3,"ench":[]},{"card":"Farm","lv":2,"ench":[]},null,null,{"card":"Soldier","lv":2,"ench":[{"card":"Steel Coat","n":1}]},null,{"card":"Soldier","lv":2,"ench":[]},null,null,null,null,null,null]'::jsonb),
 (null::uuid, 'Muralha de Balistas', 'stone',
  'Exemplo: Stronghold cercado de Ballista e Trebuchet, com Quarry na retaguarda.',
  E'Build de exemplo para mostrar como a página funciona.\n\nA ideia é segurar a horda à distância: Ballista na frente, Trebuchet atrás, e Wallmaker para ganhar tempo.',
  array['Ballisteer','Sturdy','Tactician'], array['Defensiva','Escalável'],
  '[null,null,{"card":"Wallmaker","lv":1},null,null,null,{"card":"Ballista","lv":2},{"card":"Ballista","lv":2},{"card":"Ballista","lv":2},null,null,{"card":"Trebuchet","lv":1},{"card":"Stronghold","lv":2},{"card":"Trebuchet","lv":1},null,null,null,{"card":"Quarry","lv":1},null,null,null,null,null,null,null]'::jsonb),
 (null::uuid, 'Floresta que se espalha', 'nature',
  'Exemplo: Treant no centro com Forest e Orchard espalhados para crescer o exército.',
  E'Build de exemplo para mostrar como a página funciona.\n\nForest e Orchard em volta do Treant, com Elf e Boar ocupando as bordas.',
  array['Elven','Gardener'], array['Economia'],
  '[null,null,null,null,null,null,{"card":"Elf","lv":1},{"card":"Forest","lv":2},{"card":"Boar","lv":1},null,null,{"card":"Orchard","lv":1},{"card":"Treant","lv":2},{"card":"Orchard","lv":1},null,null,{"card":"Boar","lv":1},{"card":"Forest","lv":1},{"card":"Elf","lv":1},null,null,null,null,null,null]'::jsonb)
) as seed(owner,title,king,summary,guide,perks,tags,layout)
where not exists (select 1 from public.builds where owner is null);
