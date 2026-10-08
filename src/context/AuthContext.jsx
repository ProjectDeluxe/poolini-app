import { createContext, useCallback, useContext, useEffect, useState } from "react";
import { supabase } from "../supabaseClient";
import { getMyAccount } from "../services/AccountService";

const AuthContext = createContext();

export function AuthProvider({ children }) {
  const [user, setUser] = useState(null);
  const [loading, setLoading] = useState(true);
  // Qué es este usuario (Fase 3): admin, clubs que maneja, su jugador. null = sin datos.
  const [account, setAccount] = useState(null);

  const refreshAccount = useCallback(async () => {
    try {
      setAccount(await getMyAccount());
    } catch {
      setAccount(null);
    }
  }, []);

  const userId = user && !user.isDev ? user.id : null;
  useEffect(() => {
    if (!userId) return;
    getMyAccount().then(setAccount).catch(() => setAccount(null));
  }, [userId]);

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

  // Si entra un invitado (sesión anónima), se intenta convertir ESA sesión en
  // cuenta con su celu: mismo usuario, así no pierde la partida que estaba
  // jugando. Si ese celu ya tiene cuenta, se entra normal a la cuenta existente.
  const [upgrading, setUpgrading] = useState(false);

  async function signInWithPhone(phone) {
    if (user?.is_anonymous) {
      const { error } = await supabase.auth.updateUser({ phone });
      if (!error) {
        setUpgrading(true);
        return { error: null };
      }
    }
    setUpgrading(false);
    const { error } = await supabase.auth.signInWithOtp({ phone });
    return { error };
  }

  async function verifyOtp(phone, token) {
    const { data, error } = await supabase.auth.verifyOtp({
      phone,
      token,
      type: upgrading ? "phone_change" : "sms",
    });
    if (!error) {
      setUpgrading(false);
      refreshAccount();
    }
    return { data, error };
  }

  // Invitado que escanea una mesa abierta: sesión anónima de Supabase (hay que
  // tener prendido "Anonymous sign-ins" en Auth). Si ya hay una sesión, se reusa.
  async function signInAsGuest() {
    const { data: { session } } = await supabase.auth.getSession();
    if (session) return { error: null };
    const { error } = await supabase.auth.signInAnonymously();
    return { error };
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
    <AuthContext.Provider value={{ user, loading, account: userId ? account : null, refreshAccount, signInWithPhone, verifyOtp, signInAsGuest, signOut, devLogin }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  return useContext(AuthContext);
}
