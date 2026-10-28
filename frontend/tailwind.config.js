/** @type {import('tailwindcss').Config} */
export default {
  content: ["./index.html", "./src/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        ink: "#1c1915",
        paper: "#f3eee6",
        card: "#fffdf8",
        line: "#e3d9cc",
        spruce: "#0f6e56",
        mist: "#6d655c",
        rust: "#8f3d2a",
      },
      fontFamily: {
        serif: ['"Iowan Old Style"', "Palatino", "Georgia", "serif"],
      },
      boxShadow: {
        card: "0 1px 2px rgb(28 25 21 / 0.04), 0 12px 32px rgb(28 25 21 / 0.04)",
      },
    },
  },
  plugins: [],
};
