import { useState } from "react";
import { useNavigate, useLocation } from "react-router-dom";
import { useAuth } from "../context/AuthContext";
import "./Login.css";

const COUNTRY_CODES = [
  { label: "🇦🇷 +54", value: "+54" },
  { label: "🇺🇾 +598", value: "+598" },
  { label: "🇨🇱 +56", value: "+56" },
  { label: "🇧🇷 +55", value: "+55" },
  { label: "🇺🇸 +1", value: "+1" },
];

export default function Login() {
  const { signInWithPhone, verifyOtp, devLogin } = useAuth();
  const navigate = useNavigate();
  const location = useLocation();

  const [step, setStep] = useState("phone"); // "phone" | "otp"
  const [countryCode, setCountryCode] = useState("+54");
  const [phone, setPhone] = useState("");
  const [otp, setOtp] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  const fullPhone = `${countryCode}${phone.replace(/\D/g, "")}`;
  const from = location.state?.from?.pathname || "/";

  async function handleSendOtp(e) {
    e.preventDefault();
    if (!phone.trim()) return;
    setLoading(true);
    setError("");

    const { error } = await signInWithPhone(fullPhone);

    if (error) {
      setError("No se pudo enviar el código. Revisá el número e intentá de nuevo.");
    } else {
      setStep("otp");
    }
    setLoading(false);
  }

  async function handleVerifyOtp(e) {
    e.preventDefault();
    if (otp.length < 6) return;
    setLoading(true);
    setError("");

    const { error } = await verifyOtp(fullPhone, otp);

    if (error) {
      setError("Código incorrecto o expirado. Intentá de nuevo.");
    } else {
      navigate(from, { replace: true });
    }
    setLoading(false);
  }

  function handleOtpInput(e) {
    const val = e.target.value.replace(/\D/g, "").slice(0, 6);
    setOtp(val);
  }

  return (
    <div className="login-wrapper">
      <div className="login-card">
        <div className="login-logo">🎱</div>
        <h1 className="login-title">POOLAPPDELUXE</h1>

        {step === "phone" ? (
          <>
            <p className="login-subtitle">Ingresá tu número para recibir un código por SMS</p>
            <form onSubmit={handleSendOtp} className="login-form">
              <div className="phone-input-row">
                <select
                  className="country-select"
                  value={countryCode}
                  onChange={(e) => setCountryCode(e.target.value)}
                >
                  {COUNTRY_CODES.map((c) => (
                    <option key={c.value} value={c.value}>{c.label}</option>
                  ))}
                </select>
                <input
                  className="phone-input"
                  type="tel"
                  placeholder="Ej: 1134567890"
                  value={phone}
                  onChange={(e) => setPhone(e.target.value)}
                  autoFocus
                />
              </div>
              {error && <p className="login-error">{error}</p>}
              <button
                type="submit"
                className="login-btn"
                disabled={loading || !phone.trim()}
              >
                {loading ? "Enviando..." : "RECIBIR CÓDIGO"}
              </button>
            </form>
          </>
        ) : (
          <>
            <p className="login-subtitle">
              Código enviado a <strong>{fullPhone}</strong>
            </p>
            <form onSubmit={handleVerifyOtp} className="login-form">
              <input
                className="otp-input"
                type="text"
                inputMode="numeric"
                placeholder="000000"
                value={otp}
                onChange={handleOtpInput}
                maxLength={6}
                autoFocus
              />
              {error && <p className="login-error">{error}</p>}
              <button
                type="submit"
                className="login-btn"
                disabled={loading || otp.length < 6}
              >
                {loading ? "Verificando..." : "INGRESAR"}
              </button>
              <button
                type="button"
                className="login-back"
                onClick={() => { setStep("phone"); setOtp(""); setError(""); }}
              >
                Cambiar número
              </button>
            </form>
          </>
        )}

        {/* Botón dev — solo visible en localhost */}
        {import.meta.env.DEV && (
          <div className="dev-section">
            <div className="dev-divider">
              <span>solo en desarrollo</span>
            </div>
            <button
              className="dev-btn"
              onClick={() => { devLogin(); navigate(from, { replace: true }); }}
            >
              🚧 Entrar sin cuenta
            </button>
          </div>
        )}

      </div>
    </div>
  );
}
