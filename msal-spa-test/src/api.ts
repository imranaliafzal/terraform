export async function callApim(accessToken: string, url: string, subscriptionKey?: string) {
    const headers: Record<string, string> = {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
    };
    if (subscriptionKey) headers["Ocp-Apim-Subscription-Key"] = subscriptionKey;

    const res = await fetch(url, { method: "GET", headers });
    const text = await res.text();
    return { status: res.status, text };
}
