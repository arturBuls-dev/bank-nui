import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// base './' is required so file paths work inside the game (nui://)
export default defineConfig({
  plugins: [react()],
  base: './',
  build: { outDir: 'dist' },
});
