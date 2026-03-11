FROM python:3.12-alpine

# PowerDNS auth server
RUN apk add --no-cache pdns pdns-backend-pipe

# Copy pipe backend
COPY cf-pipe-backend.py /usr/local/bin/cf-pipe-backend.py
RUN chmod +x /usr/local/bin/cf-pipe-backend.py

# Copy pdns config
COPY pdns.conf /etc/pdns/pdns.conf

EXPOSE 53/tcp 53/udp 8081/tcp

CMD ["pdns_server", "--guardian=no", "--daemon=no", "--loglevel=6"]
