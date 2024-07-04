FROM kassany/alpine-ziglang:0.13.0 as builder

WORKDIR /app

COPY build.zig .
COPY build.zig.zon .
COPY src src

RUN zig build -Doptimize=ReleaseFast

EXPOSE 3000

FROM alpine:latest

WORKDIR /app

COPY --from=builder /app/zig-out/bin/bloky.nl .

CMD ["./bloky.nl"]

