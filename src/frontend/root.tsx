import React from "react"

export default function Root({ children, manifest } : {children: React.ReactNode, manifest: string }) {
  return (    
    <html>
      <head>
        <title>Bloky.nl</title>
      </head>
      <body>
        {children}
        <script dangerouslySetInnerHTML={{__html: `window.__ROUTE_MANIFEST__ = ${manifest}`}} />
        <script src="/client.js"></script>
      </body>
    </html>
  )
}