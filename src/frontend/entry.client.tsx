import React, { StrictMode } from "react";
import { hydrateRoot } from "react-dom/client";
import App from "./app";

hydrateRoot(document, <StrictMode><App /></StrictMode>);
