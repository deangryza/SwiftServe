import { motion } from 'framer-motion';
import { FiShield, FiCalendar, FiBarChart2 } from 'react-icons/fi';
import Logo from '../../components/Logo';
import FeatureCard from '../../components/FeatureCard';
import LoginForm from '../../components/LoginForm';

const FEATURES = [
  { icon: FiShield, label: 'AI-Assisted Worker Verification' },
  { icon: FiCalendar, label: 'Booking Management' },
  { icon: FiBarChart2, label: 'Reports & Analytics' },
];

export default function Login() {
  return (
    <div className="min-h-screen w-full flex flex-col lg:flex-row bg-white">
      {/* Left: Branding panel — 40% on desktop */}
      <div className="relative lg:w-[40%] w-full min-h-[320px] lg:min-h-screen bg-gradient-to-br from-primary-700 via-primary-600 to-primary-800 flex flex-col justify-between p-8 sm:p-10 lg:p-12 overflow-hidden">
        {/* Decorative glows */}
        <div className="absolute -top-24 -right-24 w-72 h-72 bg-white/10 rounded-full blur-3xl" />
        <div className="absolute -bottom-24 -left-24 w-72 h-72 bg-white/10 rounded-full blur-3xl" />

        <motion.div
          initial={{ opacity: 0, y: -10 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.4 }}
          className="relative z-10"
        >
          <Logo variant="light" size="lg" />

          <h1 className="text-2xl sm:text-3xl font-bold text-white mt-8 leading-tight">
            SwiftServe Admin Dashboard
          </h1>
          <p className="text-white/75 text-sm sm:text-base mt-3 leading-relaxed max-w-sm">
            Manage workers, clients, bookings, reports, and platform activities from one centralized dashboard.
          </p>
        </motion.div>

        <div className="relative z-10 space-y-3 mt-8 lg:mt-0">
          {FEATURES.map((feature, i) => (
            <FeatureCard key={feature.label} icon={feature.icon} label={feature.label} delay={0.15 + i * 0.1} />
          ))}
        </div>

        <motion.p
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ duration: 0.4, delay: 0.5 }}
          className="relative z-10 text-white/50 text-xs mt-8 lg:mt-0"
        >
          Version 1.0
        </motion.p>
      </div>

      {/* Right: Login card — 60% on desktop */}
      <div className="flex-1 flex items-center justify-center p-6 sm:p-10">
        <motion.div
          initial={{ opacity: 0, y: 20, scale: 0.98 }}
          animate={{ opacity: 1, y: 0, scale: 1 }}
          transition={{ duration: 0.4 }}
          className="w-full max-w-md rounded-2xl border border-slate-100 shadow-card p-8 sm:p-10"
        >
          <div className="mb-8">
            <h2 className="text-2xl font-bold text-slate-900">Welcome Back</h2>
            <p className="text-sm text-slate-400 mt-1.5">Sign in to continue</p>
          </div>

          <LoginForm />
        </motion.div>
      </div>
    </div>
  );
}
