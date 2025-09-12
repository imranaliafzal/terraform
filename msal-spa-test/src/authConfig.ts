import type { Configuration } from "@azure/msal-browser";
import { LogLevel } from "@azure/msal-browser";


const TENANT = import.meta.env.VITE_TENANT as string;
const SPA_CLIENT_ID = import.meta.env.VITE_SPA_CLIENT_ID as string;
const REDIRECT_URI = import.meta.env.VITE_REDIRECT_URI as string;
const API_APP_CLIENT_ID = import.meta.env.VITE_API_APP_CLIENT_ID as string;
const API_SCOPE_NAME = import.meta.env.VITE_API_SCOPE_NAME as string;

// Build full API scope (e.g., api://<api-client-id>/todos.read)
export const apiScope = `api://${API_APP_CLIENT_ID}/${API_SCOPE_NAME}`;

export const msalConfig: Configuration = {
    auth: {
        clientId: SPA_CLIENT_ID,
        authority: `https://login.microsoftonline.com/${TENANT}`,
        redirectUri: REDIRECT_URI,
    },
    cache: {
        cacheLocation: "sessionStorage",
        storeAuthStateInCookie: false,
    },
    system: {
        loggerOptions: {
            loggerCallback: (level, message) => {
                if (level === LogLevel.Error) console.error(message);
            },
            piiLoggingEnabled: false,
            logLevel: LogLevel.Warning,
        },
    },
};

export const loginRequest = {
    scopes: ["openid", "profile", "offline_access", apiScope],
};
