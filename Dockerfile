FROM erlang:28-alpine AS build
COPY --from=ghcr.io/gleam-lang/gleam:v1.11.0-erlang-alpine /bin/gleam /bin/gleam
COPY . /app/
RUN cd /app && gleam export erlang-shipment

FROM erlang:28-alpine
RUN addgroup --system webapp && \
    adduser --system webapp -g webapp
COPY --from=build /app/build/erlang-shipment /app
WORKDIR /app
ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["run"]
