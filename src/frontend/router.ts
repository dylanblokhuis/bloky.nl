import * as all from "./routes/all";
import * as home from "./routes/home";
import Root from "./root";
import React from "react";

interface Request {
  path: string;
}

export interface Route {
  path: string;
  module: {
    loader?: (req: Request) => any;
    default: React.ComponentType;
  };
  loaderData?: any;
}

export const DataContext = React.createContext<Route["loaderData"]>(null);
export function useLoaderData<T>(): T {
  return React.useContext(DataContext);
}

const routes: Route[] = [
  {
    path: "/",
    module: home
  },
  // {
  //   path: "*",
  //   module: all
  // }
]

export { Root, routes }