import React from 'react';
import App from './app';

import { renderToString } from 'react-dom/server';

function onRequest(): string {

  return `<!DOCTYPE html>${renderToString(<App />)}`;
}

globalThis.onRequest = onRequest;