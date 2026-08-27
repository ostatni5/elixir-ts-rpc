import { csrfToken } from "../csrf";

// Login and logout are owned entirely by Phoenix's generated auth — the SPA
// writes none of it. Login is a server-rendered page; logout is Phoenix's
// `DELETE /users/log-out`, which we trigger by submitting a form with the
// method override + CSRF token (exactly what a Phoenix-rendered button does).
export const loginUrl = "/users/log-in";
export const registerUrl = "/users/register";

export function logout(): void {
  const form = document.createElement("form");
  form.method = "post";
  form.action = "/users/log-out";
  form.innerHTML =
    `<input type="hidden" name="_method" value="delete" />` +
    `<input type="hidden" name="_csrf_token" value="${csrfToken}" />`;
  document.body.appendChild(form);
  form.submit();
}
