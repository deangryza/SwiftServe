import { motion, useReducedMotion } from 'framer-motion';

export default function FeatureCard({ icon: Icon, label, delay = 0 }) {
  const reduceMotion = useReducedMotion();

  return (
    <motion.div
      initial={reduceMotion ? false : { opacity: 0, x: -12 }}
      animate={{ opacity: 1, x: 0 }}
      transition={{ duration: 0.35, delay: reduceMotion ? 0 : delay }}
      className="flex min-h-14 items-center gap-3 rounded-xl border border-white/15 bg-white/[0.07] px-4 py-3"
    >
      <div className="flex size-8 shrink-0 items-center justify-center rounded-lg bg-white/10">
        <Icon className="size-4 text-white" aria-hidden="true" />
      </div>
      <span className="text-sm font-medium text-white/90">{label}</span>
    </motion.div>
  );
}
