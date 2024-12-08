FROM debian:bookworm-slim

RUN apt-get update \
&& DEBIAN_FRONTEND=noninteractive apt-get install -y \
  sudo \
&& apt-get clean \
&& rm -rf /var/lib/apt/lists/*

WORKDIR /home/celery

COPY init.sh /home/celery

CMD bash
