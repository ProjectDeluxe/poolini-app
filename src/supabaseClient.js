import { createClient } from "@supabase/supabase-js";

const SUPABASE_URL = "https://kdbsbhrpbsrziklybjsv.supabase.co";

// ESTA ES TU ANON KEY, LA CORRECTA
const SUPABASE_KEY =
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtkYnNiaHJwYnNyemlrbHlianN2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUzODYzOTIsImV4cCI6MjA4MDk2MjM5Mn0.UnvBSCy2OUMZTWZoYHFQF0Aa3lfDrqiY7uk1kKgbbwE";

export const supabase = createClient(SUPABASE_URL, SUPABASE_KEY);

// Log para verificar que se carga el archivo
console.log("SUPABASE INIT OK:", SUPABASE_URL);
