# SwiftServe Admin Dashboard — Part 1: Login Page

Static-data, no-backend Login page for the SwiftServe Admin Dashboard capstone project.

## Stack

React (Vite) · Tailwind CSS · React Router DOM · React Icons · Framer Motion · react-hot-toast

## Getting Started

```bash
npm install
npm run dev
```

## Demo Credentials

- **Email:** admin@swiftserve.com
- **Password:** admin123

On success you're redirected to `/dashboard` (a placeholder page — the real
Dashboard will be generated in Part 2). On failure, a react-hot-toast error
appears and you stay on the login screen.

## Folder Structure

```
src/
  assets/
    logo.png              Placeholder SwiftServe logo
  components/
    Logo.jsx              Logo + wordmark, used on the branding panel
    FeatureCard.jsx        Small feature pill (icon + label)
    InputField.jsx          Generic labeled input with a leading icon
    PasswordField.jsx       Password input with show/hide toggle
    LoginForm.jsx            Form state, static validation, submit handling
  pages/
    Login/
      Login.jsx             Page layout: 40% branding / 60% login card
  App.jsx                  Routing (`/` → Login, `/dashboard` → placeholder)
  main.jsx                 App entry point
  index.css                Tailwind directives + shared input/button classes
```

## Notes

- All validation is local/static — no backend or Firebase calls.
- `remember me` is currently just local component state (no persistence) since
  no auth/session strategy was specified for this part.
- The `/dashboard` route is a minimal placeholder purely so navigation after
  login has somewhere to go — it is not the real Dashboard page.
