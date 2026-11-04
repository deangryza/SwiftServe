/** @type {import('tailwindcss').Config} */
export default {
  content: [
    './index.html',
    './src/**/*.{js,jsx}',
  ],
  theme: {
    extend: {
      colors: {
        primary: {
          50: '#fff9e6',
          100: '#fff3cc',
          200: '#ffe89a',
          300: '#ffdc70',
          400: '#ffd34f',
          500: '#ffc72c',
          600: '#ffc72c',
          700: '#665019',
          800: '#242424',
          900: '#242424',
        },
      },
      fontFamily: {
        sans: ['Inter', 'ui-sans-serif', 'system-ui', 'sans-serif'],
      },
      boxShadow: {
        card: '0 1px 3px 0 rgba(0,0,0,0.06), 0 1px 2px -1px rgba(0,0,0,0.06)',
        soft: '0 20px 60px -15px rgba(36, 36, 36, 0.12)',
      },
      borderRadius: {
        xl: '0.875rem',
        '2xl': '1.25rem',
      },
    },
  },
  plugins: [],
}
