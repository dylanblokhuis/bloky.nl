FROM kassany/alpine-ziglang:0.13.0 as builder

WORKDIR /app

COPY build.zig .
COPY build.zig.zon .
COPY src src

RUN zig build -Doptimize=ReleaseFast

FROM scratch

EXPOSE 3000
WORKDIR /app

COPY --from=builder /app/zig-out/bin/bloky.nl .
COPY --from=builder /app/public public

CMD ["./bloky.nl"]

