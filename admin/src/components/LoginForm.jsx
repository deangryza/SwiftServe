import { useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { ArrowRight, Eye, EyeOff, LockKeyhole, Mail, ShieldCheck } from 'lucide-react';
import toast from 'react-hot-toast';
import {
  browserLocalPersistence,
  browserSessionPersistence,
  setPersistence,
  signInWithEmailAndPassword,
  signOut,
} from 'firebase/auth';

import { auth } from '../lib/firebase';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Checkbox } from '@/components/ui/checkbox';
import { Field, FieldError, FieldGroup, FieldLabel } from '@/components/ui/field';
import { Input } from '@/components/ui/input';

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function getAuthErrorMessage(error) {
  if (error?.message === 'This account does not have administrator access.') return error.message;

  switch (error?.code) {
    case 'auth/invalid-credential':
    case 'auth/user-not-found':
    case 'auth/wrong-password':
      return 'The email or password is incorrect. Check your details and try again.';
    case 'auth/too-many-requests':
      return 'Sign-in is temporarily limited after several attempts. Please wait and try again.';
    case 'auth/network-request-failed':
      return 'We could not reach the sign-in service. Check your connection and try again.';
    default:
      return 'Unable to sign in right now. Try again or contact support.';
  }
}

export default function LoginForm() {
  const navigate = useNavigate();
  const errorSummaryRef = useRef(null);
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [remember, setRemember] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [showPassword, setShowPassword] = useState(false);
  const [emailTouched, setEmailTouched] = useState(false);
  const [passwordTouched, setPasswordTouched] = useState(false);
  const [formError, setFormError] = useState('');

  const emailError = emailTouched && !EMAIL_PATTERN.test(email.trim()) ? 'Enter a valid email address.' : '';
  const passwordError = passwordTouched && !password ? 'Enter your password.' : '';

  const handleSubmit = async (event) => {
    event.preventDefault();
    setEmailTouched(true);
    setPasswordTouched(true);
    setFormError('');

    if (!EMAIL_PATTERN.test(email.trim()) || !password) {
      requestAnimationFrame(() => errorSummaryRef.current?.focus());
      return;
    }

    setSubmitting(true);
    try {
      await setPersistence(auth, remember ? browserLocalPersistence : browserSessionPersistence);
      const credential = await signInWithEmailAndPassword(auth, email.trim(), password);
      const token = await credential.user.getIdTokenResult(true);
      if (token.claims.admin !== true) {
        await signOut(auth);
        throw new Error('This account does not have administrator access.');
      }
      toast.success('Welcome back, Administrator!');
      navigate('/dashboard', { replace: true });
    } catch (error) {
      setFormError(getAuthErrorMessage(error));
      requestAnimationFrame(() => errorSummaryRef.current?.focus());
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div>
      <Badge variant="secondary" className="mb-5 bg-primary-50 text-primary-700">
        <ShieldCheck data-icon="inline-start" aria-hidden="true" />
        Admin console
      </Badge>
      <h2 className="text-3xl font-semibold tracking-[-0.035em] text-slate-950">Welcome back</h2>
      <p className="mt-2 text-sm text-slate-500">Use your authorized administrator account.</p>

      <form onSubmit={handleSubmit} className="mt-8" noValidate>
        {(formError || emailError || passwordError) && (
          <div ref={errorSummaryRef} role="alert" tabIndex={-1} className="mb-5 rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-800 focus:outline-none focus:ring-2 focus:ring-red-500 focus:ring-offset-2">
            <p className="font-medium">We could not sign you in.</p>
            <p className="mt-1 text-red-700">{formError || emailError || passwordError}</p>
          </div>
        )}

        <FieldGroup>
          <Field data-invalid={Boolean(emailError)}>
            <FieldLabel htmlFor="admin-email">Email address</FieldLabel>
            <div className="relative">
              <Mail className="pointer-events-none absolute left-3 top-1/2 z-10 size-4 -translate-y-1/2 text-slate-400" aria-hidden="true" />
              <Input
                id="admin-email"
                type="email"
                value={email}
                onChange={(event) => { setEmail(event.target.value); setFormError(''); }}
                onBlur={() => setEmailTouched(true)}
                placeholder="admin@swiftserve.com"
                autoComplete="email"
                disabled={submitting}
                aria-invalid={Boolean(emailError)}
                aria-describedby={emailError ? 'admin-email-error' : undefined}
                className="h-11 bg-white pl-10"
                required
              />
            </div>
            <FieldError id="admin-email-error">{emailError}</FieldError>
          </Field>

          <Field data-invalid={Boolean(passwordError)}>
            <FieldLabel htmlFor="admin-password">Password</FieldLabel>
            <div className="relative">
              <LockKeyhole className="pointer-events-none absolute left-3 top-1/2 z-10 size-4 -translate-y-1/2 text-slate-400" aria-hidden="true" />
              <Input
                id="admin-password"
                type={showPassword ? 'text' : 'password'}
                value={password}
                onChange={(event) => { setPassword(event.target.value); setFormError(''); }}
                onBlur={() => setPasswordTouched(true)}
                placeholder="Enter your password"
                autoComplete="current-password"
                disabled={submitting}
                aria-invalid={Boolean(passwordError)}
                aria-describedby={passwordError ? 'admin-password-error' : undefined}
                className="h-11 bg-white pl-10 pr-11"
                required
              />
              <Button type="button" variant="ghost" size="icon" onClick={() => setShowPassword((visible) => !visible)} disabled={submitting} className="absolute right-1 top-1/2 size-9 -translate-y-1/2 text-slate-500 hover:bg-slate-100 hover:text-slate-900" aria-label={showPassword ? 'Hide password' : 'Show password'}>
                {showPassword ? <EyeOff aria-hidden="true" /> : <Eye aria-hidden="true" />}
              </Button>
            </div>
            <FieldError id="admin-password-error">{passwordError}</FieldError>
          </Field>

          <div className="flex min-h-11 items-center justify-between gap-4">
            <Field orientation="horizontal" className="w-auto items-center gap-2">
              <Checkbox id="remember-device" checked={remember} onCheckedChange={setRemember} disabled={submitting} />
              <FieldLabel htmlFor="remember-device" className="cursor-pointer text-sm font-normal text-slate-600">Keep me signed in</FieldLabel>
            </Field>
            <a href="mailto:support@swiftserve.com?subject=Admin%20access%20help" className="rounded-sm text-sm font-medium text-primary-700 underline-offset-4 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2">Need help?</a>
          </div>

          <Button type="submit" size="lg" disabled={submitting} className="h-11 w-full bg-primary-600 text-white shadow-card hover:bg-primary-700">
            {submitting ? 'Signing in…' : 'Sign in to dashboard'}
            {!submitting && <ArrowRight data-icon="inline-end" aria-hidden="true" />}
          </Button>
        </FieldGroup>
      </form>

      <div className="mt-6 flex items-center gap-2 text-xs text-slate-500">
        <ShieldCheck className="size-4 text-primary-600" aria-hidden="true" />
        Protected by role-based administrator access
      </div>
    </div>
  );
}
