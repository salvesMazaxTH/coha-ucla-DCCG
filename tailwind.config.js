/** @type {import('tailwindcss').Config} */
export default {
  content: ["./index.html", "./public/**/*.{html,js}"],
  theme: {
    extend: {
      fontFamily: {
        sans: ["Montserrat", "sans-serif"],
      },
      colors: {
        "game-dark": "#0a0e27",
        "game-darker": "#050812",
        "neon-green": "#00ff41",
        "neon-green-dark": "#00cc33",
        "card-bg": "#1a1f3a",
        "board-divider": "#00ff41",
      },
      boxShadow: {
        "neon-glow": "0 0 20px rgba(0, 255, 65, 0.6)",
        "neon-glow-lg": "0 0 30px rgba(0, 255, 65, 0.8)",
        "deep-inset": "inset 0 2px 4px rgba(0, 0, 0, 0.6)",
      },
      backgroundImage: {
        "gradient-dark": "linear-gradient(135deg, #0a0e27 0%, #1a1f3a 100%)",
        "gradient-dark-alt":
          "linear-gradient(135deg, #050812 0%, #0a0e27 100%)",
        "gradient-red": "linear-gradient(135deg, #ff3333 0%, #cc0000 100%)",
      },
    },
  },
  plugins: [],
};
