import React from "react";
import { renderToString } from "react-dom/server";
import { routes, Root, DataContext } from "./router";

function onRequest(path: string): string {
  const route = routes.find((route) => path.startsWith(route.path));
  if (!route) {
    throw new Error("No route found");
  }

  const data = route.module.loader?.({
    path,
  });
  route.loaderData = data;

  return `<!DOCTYPE html>${renderToString(
    <DataContext.Provider value={data}>
      <Root manifest={JSON.stringify(routes)}>
        <route.module.default />
      </Root>
    </DataContext.Provider>
  )}`;
}

globalThis.onRequest = onRequest;
