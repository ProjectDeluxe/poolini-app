import { createContext, useContext, useEffect, useState } from "react";
import { supabase } from "../supabaseClient";

const AuthContext = createContext();

export function AuthProvider({ children }) {
  const [user, setUser] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    // Sesion inicial
    supabase.auth.getSession().then(({ data: { session } }) => {
      setUser(session?.user ?? null);
      setLoading(false);
    });

    // Escucha cambios de auth
    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, session) => {
      setUser(session?.user ?? null);
    });

    return () => subscription.unsubscribe();
  }, []);

  async function signInWithPhone(phone) {
    const { error } = await supabase.auth.signInWithOtp({ phone });
    return { error };
  }

  async function verifyOtp(phone, token) {
    const { data, error } = await supabase.auth.verifyOtp({
      phone,
      token,
      type: "sms",
    });
    return { data, error };
  }

  async function signOut() {
    await supabase.auth.signOut();
    // limpia también el usuario dev si lo había
    setUser(null);
  }

  // Solo para desarrollo local — no aparece en producción
  function devLogin() {
    setUser({ id: "dev-user", phone: "+54dev", email: "dev@poolappdeluxe.local", isDev: true });
  }

  return (
    <AuthContext.Provider value={{ user, loading, signInWithPhone, verifyOtp, signOut, devLogin }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  return useContext(AuthContext);
}
