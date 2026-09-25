import logo from '../assets/logo.png';

/**
 * Logo
 * Renders the SwiftServe mark plus wordmark.
 * `variant="light"` is used on the dark/blue branding panel,
 * `variant="dark"` would render dark text on a light background if reused elsewhere.
 */
export default function Logo({ variant = 'light', size = 'md' }) {
  const textColor = variant === 'light' ? 'text-white' : 'text-slate-900';
  const imgSize = size === 'lg' ? 'w-11 h-11' : 'w-9 h-9';

  return (
    <div className="flex items-center gap-3">
      <img src={logo} alt="SwiftServe logo" className={`${imgSize} rounded-xl shadow-card object-cover`} />
      <span className={`font-bold text-lg tracking-tight ${textColor}`}>SwiftServe</span>
    </div>
  );
}
