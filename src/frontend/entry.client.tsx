import React from "react";
import { hydrateRoot } from "react-dom/client";
import { routes, Root, Route, DataContext } from "./router";

// @ts-ignore
const manifest: Route[] = window.__ROUTE_MANIFEST__;

const routeIndex = routes.findIndex((route) => location.pathname.startsWith(route.path));
if (routeIndex === -1) {
  throw new Error("No route found");
}

const route = routes[routeIndex];
route.loaderData = manifest[routeIndex].loaderData;

hydrateRoot(
  document,
  <DataContext.Provider value={route.loaderData}>
    <Root manifest={JSON.stringify(manifest)}>
      <route.module.default />
    </Root>
  </DataContext.Provider>
);
