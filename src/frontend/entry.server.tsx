import React from 'react';
import App from './app';

import { renderToString } from 'react-dom/server';

function onRequest(path: string): string {

  return renderToString(<App path={path} />);
}

globalThis.onRequest = onRequest;