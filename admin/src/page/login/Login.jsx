import { motion, useReducedMotion } from 'framer-motion';
import { CalendarClock, ChartNoAxesCombined, ShieldCheck } from 'lucide-react';
import Logo from '../../components/Logo';
import FeatureCard from '../../components/FeatureCard';
import LoginForm from '../../components/LoginForm';

const FEATURES = [
  { icon: ShieldCheck, label: 'Worker verification' },
  { icon: CalendarClock, label: 'Booking oversight' },
  { icon: ChartNoAxesCombined, label: 'Reports and insights' },
];

export default function Login() {
  const reduceMotion = useReducedMotion();

  return (
    <main className="flex min-h-svh w-full flex-col bg-slate-50 lg:flex-row">
      <section className="flex min-h-[300px] w-full flex-col justify-between overflow-hidden bg-primary-800 p-7 sm:p-10 lg:min-h-svh lg:w-[42%] lg:p-12 xl:p-16">
        <motion.div initial={reduceMotion ? false : { opacity: 0, y: -10 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: reduceMotion ? 0 : 0.35 }}>
          <Logo variant="light" size="lg" />
          <h1 className="mt-10 max-w-md text-3xl font-semibold leading-[1.08] tracking-[-0.04em] text-white sm:text-4xl xl:text-5xl">
            Run the platform with confidence.
          </h1>
          <p className="mt-4 max-w-md text-sm leading-6 text-primary-100 sm:text-base">
            Secure access to daily operations, trust, and service performance.
          </p>
        </motion.div>

        <div className="mt-10 grid gap-3 sm:grid-cols-3 lg:mt-16 lg:grid-cols-1">
          {FEATURES.map((feature, index) => (
            <FeatureCard key={feature.label} icon={feature.icon} label={feature.label} delay={0.1 + index * 0.08} />
          ))}
        </div>

        <motion.p initial={reduceMotion ? false : { opacity: 0 }} animate={{ opacity: 1 }} transition={{ duration: reduceMotion ? 0 : 0.35, delay: reduceMotion ? 0 : 0.35 }} className="mt-8 text-xs text-primary-200/70">
          SwiftServe Console · Version 1.0
        </motion.p>
      </section>

      <section className="flex flex-1 items-center justify-center px-6 py-12 sm:px-10 lg:px-16">
        <motion.div initial={reduceMotion ? false : { opacity: 0, y: 20, scale: 0.98 }} animate={{ opacity: 1, y: 0, scale: 1 }} transition={{ duration: reduceMotion ? 0 : 0.35 }} className="w-full max-w-md">
          <LoginForm />
        </motion.div>
      </section>
    </main>
  );
}
