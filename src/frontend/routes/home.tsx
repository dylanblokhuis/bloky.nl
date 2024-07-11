import React from 'react'
import { useLoaderData } from '../router'

export function loader() {
    return {
        hey: "Hello"
    }
}

function Home(props: {}) {
    const ctx = useLoaderData();

    return (
        <div>Home! {JSON.stringify(ctx)}</div>
    )
}

export default Home
