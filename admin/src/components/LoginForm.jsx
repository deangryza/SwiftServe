import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { motion } from 'framer-motion';
import { FiMail, FiArrowRight } from 'react-icons/fi';
import toast from 'react-hot-toast';
import {
  browserLocalPersistence,
  browserSessionPersistence,
  setPersistence,
  signInWithEmailAndPassword,
  signOut,
} from 'firebase/auth';

import InputField from './InputField';
import PasswordField from './PasswordField';
import { auth } from '../lib/firebase';

export default function LoginForm() {
  const navigate = useNavigate();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [remember, setRemember] = useState(true);
  const [submitting, setSubmitting] = useState(false);

  const handleSubmit = async (event) => {
    event.preventDefault();
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
      toast.error(error.message || 'Unable to sign in.');
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <motion.form initial={{ opacity: 0, y: 16 }} animate={{ opacity: 1, y: 0 }} onSubmit={handleSubmit} className="space-y-5">
      <InputField label="Email Address" icon={FiMail} type="email" value={email} onChange={(event) => setEmail(event.target.value)} placeholder="admin@swiftserve.com" autoComplete="email" required />
      <PasswordField label="Password" value={password} onChange={(event) => setPassword(event.target.value)} placeholder="Enter your password" required />
      <label className="flex items-center gap-2 text-sm text-slate-500 cursor-pointer select-none">
        <input type="checkbox" checked={remember} onChange={(event) => setRemember(event.target.checked)} className="rounded border-slate-300 text-primary-600 focus:ring-primary-500" />
        Remember me
      </label>
      <motion.button type="submit" disabled={submitting} whileTap={{ scale: 0.98 }} className="btn-primary">
        {submitting ? 'Signing in…' : <>Sign In <FiArrowRight className="w-4 h-4" /></>}
      </motion.button>
    </motion.form>
  );
}
