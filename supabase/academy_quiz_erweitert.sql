-- P² Sales MultiTool: Academy-Prüfung erweitert von 8 auf 21 Fragen (V2.39). Darf mehrfach ausgeführt werden.
-- Die Fragen q9 bis q21 stehen in der App (index.html, A_QUIZ), die Lösungen nur hier (academy_quiz_key).
-- Die Zahl ist der Index der richtigen Antwort (0 = erste, 1 = zweite, 2 = dritte).
-- WICHTIG: Reihenfolge der Antworten in der App und diese Lösungen müssen zusammenpassen.
-- Bestanden ist weiter ab 75 % (bei 21 Fragen: 16 richtig). Bereits bestandene Prüfungen bleiben gültig.
insert into public.academy_quiz_key (qid, correct) values
  ('q9', 0),
  ('q10', 2),
  ('q11', 1),
  ('q12', 0),
  ('q13', 1),
  ('q14', 0),
  ('q15', 2),
  ('q16', 0),
  ('q17', 0),
  ('q18', 1),
  ('q19', 1),
  ('q20', 2),
  ('q21', 0)
on conflict (qid) do update set correct = excluded.correct;
