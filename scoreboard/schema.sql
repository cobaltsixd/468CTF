create table if not exists submissions (
  id integer primary key,
  student text,
  team text,
  challenge text,
  flag text,
  correct integer,
  points integer,
  ts integer
);
create table if not exists solves (
  student text,
  challenge text,
  primary key (student, challenge)
);
