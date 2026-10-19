import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App';
import './index.css';
import { isInGame } from './nui';

// In a browser draw a dark background instead of a transparent one, so the window looks like it does in game
if (!isInGame()) document.documentElement.classList.add('dev');

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);
