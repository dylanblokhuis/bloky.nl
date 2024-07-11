import React from "react"

export default function App() {
  const [count, setCount] = React.useState(0)

  return (    
    <html>
      <head>
        <title>Bloky.nl</title>
      </head>
      <body>
        <h1>Bloky.nl</h1>
        <p>Random counter: {count}</p>
        <button onClick={() => setCount(count + 1)}>Increment</button>

        <script src="/client.js"></script>
      </body>
    </html>
  )
}