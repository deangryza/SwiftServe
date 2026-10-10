export default function DataState({ loading, error }) {
  if (!loading && !error) return null;
  return <div role={error ? 'alert' : 'status'} className="rounded-xl bg-white p-5 mb-4 text-sm">{error ? `Could not load data: ${error}` : 'Loading records…'}</div>;
}
