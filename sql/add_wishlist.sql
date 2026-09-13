-- Liste d'envie : les usagers peuvent marquer des livres d'intérêt, y compris
-- ceux actuellement indisponibles à la médiathèque.

create table public.wishlist (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  book_id bigint not null references public.books(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (user_id, book_id)
);

alter table public.wishlist enable row level security;

create policy "Un usager voit sa propre liste d'envie"
  on public.wishlist for select
  using (auth.uid() = user_id);

create policy "Un usager ajoute à sa propre liste d'envie"
  on public.wishlist for insert
  with check (auth.uid() = user_id);

create policy "Un usager retire de sa propre liste d'envie"
  on public.wishlist for delete
  using (auth.uid() = user_id);
