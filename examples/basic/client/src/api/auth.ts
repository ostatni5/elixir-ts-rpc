// Login and logout live outside the RPC manifest because they mutate the
// session cookie. RPC handlers can't write to the response, so the server
// exposes them as plain HTTP endpoints under /auth/*.
type LoginOk = { id: string; email: string };
type LoginResponse = { ok?: LoginOk; error?: { message: string } };

export async function login(username: string, password: string): Promise<LoginOk> {
  const res = await fetch("/auth/login", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    credentials: "include",
    body: JSON.stringify({ username, password }),
  });
  const data = (await res.json()) as LoginResponse;
  if (!res.ok || data.error) {
    throw new Error(data.error?.message ?? "login failed");
  }
  return data.ok!;
}

export async function logout(): Promise<void> {
  const res = await fetch("/auth/logout", {
    method: "POST",
    credentials: "include",
  });
  if (!res.ok) {
    throw new Error("logout failed");
  }
}
