-- Script utilitário para bootstrap manual (executado via make init quando necessário).
CREATE TABLE IF NOT EXISTS ha_lab_meta (
  key text PRIMARY KEY,
  value text NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);
