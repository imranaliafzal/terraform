import { useEffect, useMemo, useState } from "react";
import { useMsal, useAccount } from "@azure/msal-react";
import { InteractionRequiredAuthError } from "@azure/msal-browser";
import { loginRequest, apiScope } from "./authConfig";
import { callApim } from "./api";

const DEFAULT_APIM_URL = import.meta.env.VITE_APIM_URL as string;
const DEFAULT_SUB_KEY = (import.meta.env.VITE_APIM_SUBSCRIPTION_KEY as string) || "";

export default function App() {
    const { instance, accounts } = useMsal();
    const active = instance.getActiveAccount() ?? accounts[0] ?? null;
    const account = useAccount(active || undefined);

    const [apimUrl, setApimUrl] = useState(DEFAULT_APIM_URL);
    const [subKey, setSubKey] = useState(DEFAULT_SUB_KEY);
    const [token, setToken] = useState("");
    const [resp, setResp] = useState("Ready.");

    // Ensure an active account stays set when accounts list changes
    useEffect(() => {
        if (!instance.getActiveAccount() && accounts.length > 0) {
            instance.setActiveAccount(accounts[0]);
        }
    }, [accounts, instance]);

    const scopes = useMemo(() => loginRequest.scopes, []);

    const signIn = async () => {
        await instance.loginRedirect({ scopes });
    };

    const signOut = async () => {
        const a = instance.getActiveAccount();
        await instance.logoutRedirect({ account: a ?? undefined });
    };

    const getAccessToken = async (): Promise<string> => {
        const acc = instance.getActiveAccount();
        if (!acc) {
            setResp("No user signed in. Click Sign in.");
            throw new Error("no_account");
        }
        try {
            const res = await instance.acquireTokenSilent({ ...loginRequest, account: acc });
            return res.accessToken;
        } catch (e: any) {
            if (e instanceof InteractionRequiredAuthError || e.errorCode === "interaction_required") {
                await instance.acquireTokenRedirect({ ...loginRequest, account: acc });
                return ""; // will continue after redirect
            }
            throw e;
        }
    };

    const fetchToken = async () => {
        try {
            setResp("Acquiring token...");
            const t = await getAccessToken();
            if (t) {
                setToken(t);
                setResp("Token acquired. You can call APIM now.");
            }
        } catch (e: any) {
            setResp(`Token error: ${e.message || e.toString()}`);
        }
    };

    const callApi = async () => {
        try {
            setResp("Calling APIM...");
            const t = token || (await getAccessToken());
            if (!t) return; // redirect path
            setToken(t);
            const { status, text } = await callApim(t, apimUrl, subKey || undefined);
            setResp(`HTTP ${status}\n${text}`);
        } catch (e: any) {
            setResp(`Call error: ${e.message || e.toString()}`);
        }
    };

    return (
        <div style={{ fontFamily: "system-ui, -apple-system, Segoe UI, Roboto", maxWidth: 900, margin: "2rem auto", padding: "0 1rem" }}>
            <h1>MSAL (Auth Code + PKCE) → APIM test</h1>

            <div style={{ display: "flex", gap: 8, flexWrap: "wrap", margin: "8px 0" }}>
                <button onClick={signIn}>Sign in</button>
                <button onClick={fetchToken}>Get/Refresh Token</button>
                <button onClick={callApi}>Call APIM</button>
                <button onClick={signOut}>Sign out</button>
                <span style={{ border: "1px solid #ccc", padding: "2px 6px", borderRadius: 4 }}>
          {account ? `Signed in: ${account.username}` : "Not signed in"}
        </span>
            </div>

            <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 16 }}>
                <div>
                    <label>APIM URL</label>
                    <input style={{ width: "100%", padding: 8 }} value={apimUrl} onChange={(e) => setApimUrl(e.target.value)} />
                </div>
                <div>
                    <label>Ocp-Apim-Subscription-Key (optional)</label>
                    <input style={{ width: "100%", padding: 8 }} value={subKey} onChange={(e) => setSubKey(e.target.value)} />
                </div>
            </div>

            <p><strong>Scope requested:</strong> <code>{apiScope}</code></p>

            <h3>HTTP Response</h3>
            <pre style={{ fontFamily: "ui-monospace, Menlo, Consolas", fontSize: 12, whiteSpace: "pre-wrap", background: "#f6f6f6", padding: 8 }}>
        {resp}
      </pre>

            <h3>Access Token (raw JWT)</h3>
            <textarea readOnly style={{ width: "100%", height: 200, fontFamily: "ui-monospace, Menlo, Consolas", fontSize: 12 }} value={token} />
        </div>
    );
}
