import { motion } from 'framer-motion';

/**
 * FeatureCard
 * Small glassy card used on the branding panel to list what the
 * dashboard lets an admin do. Purely presentational / static content.
 */
export default function FeatureCard({ icon: Icon, label, delay = 0 }) {
  return (
    <motion.div
      initial={{ opacity: 0, x: -12 }}
      animate={{ opacity: 1, x: 0 }}
      transition={{ duration: 0.4, delay }}
      className="flex items-center gap-3 rounded-xl bg-white/10 border border-white/15 backdrop-blur-sm px-4 py-3 hover:bg-white/15 transition-colors duration-150"
    >
      <div className="w-8 h-8 rounded-lg bg-white/15 flex items-center justify-center shrink-0">
        <Icon className="w-4 h-4 text-white" />
      </div>
      <span className="text-sm font-medium text-white/90">{label}</span>
    </motion.div>
  );
}
