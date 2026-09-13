-- Un avis ne peut être laissé que sur un livre réellement emprunté et rendu
-- (visible dans l'historique), jamais depuis le catalogue avant même de
-- l'avoir lu. Le catalogue n'affiche plus que les avis déjà existants.
-- + notification automatique quand le livre entre dans l'historique
-- (délai de 3 semaines écoulé), pour inviter l'usager à le noter.

-- 1. Un avis ne peut être créé/modifié que si l'usager a bien emprunté ce
-- livre ('recupere') et que le délai de prêt de 3 semaines est terminé.
drop policy if exists "Un usager dépose son propre avis" on public.book_reviews;
create policy "Un usager dépose un avis uniquement sur un livre emprunté et rendu"
  on public.book_reviews for insert
  with check (
    auth.uid() = user_id
    and exists (
      select 1 from public.reservations r
      where r.user_id = auth.uid()
        and r.book_id = book_reviews.book_id
        and r.status = 'recupere'
        and r.return_due_at is not null
        and r.return_due_at <= now()
    )
  );

drop policy if exists "Un usager modifie son propre avis" on public.book_reviews;
create policy "Un usager modifie un avis uniquement sur un livre emprunté et rendu"
  on public.book_reviews for update
  using (
    auth.uid() = user_id
    and exists (
      select 1 from public.reservations r
      where r.user_id = auth.uid()
        and r.book_id = book_reviews.book_id
        and r.status = 'recupere'
        and r.return_due_at is not null
        and r.return_due_at <= now()
    )
  );

-- 2. Notification une fois le livre rendu (délai de 3 semaines écoulé), pour
-- inviter l'usager à le noter dans son historique de réservations.
alter table public.reservations add column if not exists review_reminded boolean not null default false;

create or replace function public.remind_to_review_returned_books()
returns void
language plpgsql
security definer
as $$
begin
  insert into public.notifications (user_id, message)
  select r.user_id, 'Alors, qu''as-tu pensé de « ' || b.title || ' » ? Donne ton avis dans ton historique de réservations !'
  from public.reservations r
  join public.books b on b.id = r.book_id
  where r.status = 'recupere'
    and r.review_reminded = false
    and r.return_due_at is not null
    and r.return_due_at <= now();

  update public.reservations
  set review_reminded = true
  where status = 'recupere' and review_reminded = false and return_due_at is not null and return_due_at <= now();
end;
$$;

select cron.schedule('remind-to-review-returned-books', '0 10 * * *', $$select public.remind_to_review_returned_books();$$);
