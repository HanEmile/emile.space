# Postgres Docker-Compose

This is a basic dockerfile for quickly setting up a postgres database and pgadmin4.

Make sure to change the passwords!

[docker-compose.yml](./docker-compose.yml)

version: "3"

services:
  postgres:
    image: postgres:12.1
    hostname: postgres
    ports:
      - "5432:5432"
    environment:
      POSTGRES_USER: CHANGEME
      POSTGRES_PASSWORD: CHANGEME
    volumes:
      - postgres_volume:/var/lib/postgresql
    networks:
      - database
    restart: unless-stopped

  pgadmin:
    image: dpage/pgadmin4
    ports:
      - "5554:80"
    environment:
      PGADMIN_DEFAULT_EMAIL: CHANGEME
      PGADMIN_DEFAULT_PASSWORD: CHANGEME
    restart: unless-stopped
    networks:
      - database

volumes:
  postgres_volume: {}

networks:
  database: