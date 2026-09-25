import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { motion } from 'framer-motion';
import { FiMail, FiArrowRight } from 'react-icons/fi';
import toast from 'react-hot-toast';
import InputField from './InputField';
import PasswordField from './PasswordField';

// Static demo credentials — no backend, no Firebase.
const ADMIN_CREDENTIALS = {
  email: 'admin@swiftserve.com',
  password: 'admin123',
};

/**
 * LoginForm
 * Handles all login state + static validation, then hands off to
 * react-router-dom for navigation and react-hot-toast for feedback.
 */
export default function LoginForm() {
  const navigate = useNavigate();

  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [remember, setRemember] = useState(true);
  const [submitting, setSubmitting] = useState(false);

  const handleSubmit = (e) => {
    e.preventDefault();
    setSubmitting(true);

    // Simulate a brief network delay so the button/loading state feels real.
    setTimeout(() => {
      setSubmitting(false);
      const isValid = email.trim() === ADMIN_CREDENTIALS.email && password === ADMIN_CREDENTIALS.password;

      if (isValid) {
        toast.success('Welcome back, Administrator!');
        navigate('/dashboard');
      } else {
        toast.error('Invalid email or password. Please try again.');
      }
    }, 600);
  };

  return (
    <motion.form
      initial={{ opacity: 0, y: 16 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.4 }}
      onSubmit={handleSubmit}
      className="space-y-5"
    >
      <InputField
        label="Email Address"
        icon={FiMail}
        type="email"
        value={email}
        onChange={(e) => setEmail(e.target.value)}
        placeholder="admin@swiftserve.com"
        autoComplete="email"
        required
      />

      <PasswordField
        label="Password"
        value={password}
        onChange={(e) => setPassword(e.target.value)}
        placeholder="Enter your password"
        required
      />

      <div className="flex items-center justify-between text-sm">
        <label className="flex items-center gap-2 text-slate-500 cursor-pointer select-none">
          <input
            type="checkbox"
            checked={remember}
            onChange={(e) => setRemember(e.target.checked)}
            className="rounded border-slate-300 text-primary-600 focus:ring-primary-500"
          />
          Remember me
        </label>
        <button
          type="button"
          onClick={() => toast('Password reset link sent (demo only).', { icon: '📩' })}
          className="text-primary-600 font-medium hover:underline"
        >
          Forgot password?
        </button>
      </div>

      <motion.button
        type="submit"
        disabled={submitting}
        whileTap={{ scale: 0.98 }}
        className="btn-primary"
      >
        {submitting ? (
          'Signing in...'
        ) : (
          <>
            Sign In <FiArrowRight className="w-4 h-4" />
          </>
        )}
      </motion.button>

      <div className="relative flex items-center py-1">
        <div className="flex-1 border-t border-slate-200" />
        <span className="px-3 text-xs font-medium text-slate-400">Demo Credentials</span>
        <div className="flex-1 border-t border-slate-200" />
      </div>

      <div className="rounded-xl bg-slate-50 border border-slate-100 px-4 py-3 text-xs text-slate-500 space-y-1">
        <p className="flex justify-between">
          <span>Email</span>
          <span className="font-medium text-slate-700">admin@swiftserve.com</span>
        </p>
        <p className="flex justify-between">
          <span>Password</span>
          <span className="font-medium text-slate-700">admin123</span>
        </p>
      </div>
    </motion.form>
  );
}
