import React from 'react';
import ReactDOM from 'react-dom/client';
import ElectionAssistant from './election-assistant.jsx';
import { GoogleOAuthProvider } from '@react-oauth/google';

const root = ReactDOM.createRoot(document.getElementById('root'));
root.render(
  <React.StrictMode>
    <GoogleOAuthProvider clientId={process.env.REACT_APP_GOOGLE_CLIENT_ID}>
      <ElectionAssistant />
    </GoogleOAuthProvider>
  </React.StrictMode>
);
