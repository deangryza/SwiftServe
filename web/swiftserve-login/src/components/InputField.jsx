/**
 * InputField
 * Generic labeled text input with a leading icon.
 * Kept deliberately simple/reusable so it can be dropped into any future
 * form (not just the login form) without modification.
 */
export default function InputField({
  label,
  icon: Icon,
  type = 'text',
  value,
  onChange,
  placeholder,
  required = false,
  autoComplete,
}) {
  return (
    <div>
      <label className="block text-xs font-medium text-slate-600 mb-1.5">{label}</label>
      <div className="relative">
        {Icon && <Icon className="absolute left-3.5 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-400" />}
        <input
          type={type}
          value={value}
          onChange={onChange}
          placeholder={placeholder}
          required={required}
          autoComplete={autoComplete}
          className={`input-field ${Icon ? 'pl-10' : ''}`}
        />
      </div>
    </div>
  );
}
