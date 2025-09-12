import React from "react";
import ReactDOM from "react-dom/client";
import { MsalProvider } from "@azure/msal-react";
import { msalInstance } from "./msal";
import App from "./App";
import "./index.css";

// Simple error boundary so runtime errors show on screen
class ErrorBoundary extends React.Component<{ children: React.ReactNode }, { hasError: boolean; msg: string }> {
    constructor(props: any) {
        super(props);
        this.state = { hasError: false, msg: "" };
    }
    static getDerivedStateFromError(error: any) {
        return { hasError: true, msg: String(error) };
    }
    componentDidCatch(error: any, info: any) {
        console.error("Render error:", error, info);
    }
    render() {
        if (this.state.hasError) {
            return (
                <pre style={{ padding: 12, background: "#ffecec", color: "#a40000", whiteSpace: "pre-wrap" }}>
          {this.state.msg}
        </pre>
            );
        }
        return this.props.children;
    }
}

const rootEl = document.getElementById("root")!;
const root = ReactDOM.createRoot(rootEl);

// Bootstrap MSAL (v3 requires initialize()) BEFORE any other MSAL API
(async () => {
    // Optional: show a quick splash while initializing
    root.render(<div style={{ padding: 16, fontFamily: "system-ui" }}>Initializing authentication…</div>);

    try {
        await msalInstance.initialize(); // <-- REQUIRED on msal-browser v3+

        const resp = await msalInstance.handleRedirectPromise();
        if (resp?.account) {
            msalInstance.setActiveAccount(resp.account);
        } else {
            const accounts = msalInstance.getAllAccounts();
            if (accounts.length > 0) msalInstance.setActiveAccount(accounts[0]);
        }
    } catch (e) {
        console.error("MSAL init/redirect error:", e);
    }

    // Now render the real app once MSAL is ready
    root.render(
        <React.StrictMode>
            <MsalProvider instance={msalInstance}>
                <ErrorBoundary>
                    <App />
                </ErrorBoundary>
            </MsalProvider>
        </React.StrictMode>
    );
})();
