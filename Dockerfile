FROM kassany/alpine-ziglang:0.13.0 as builder

WORKDIR /app

USER root

COPY build.zig .
COPY build.zig.zon .
COPY src src
COPY public public
COPY package.json .
COPY package-lock.json .

RUN apk add --update nodejs npm

RUN npm install
RUN npm run build

RUN zig build -Doptimize=ReleaseFast

FROM scratch

EXPOSE 3000
WORKDIR /app

# copy libc
COPY --from=builder /lib/ld-musl-* /lib/

COPY --from=builder /app/zig-out zig-out
COPY --from=builder /app/public public

CMD ["./zig-out/bin/bloky.nl"]

