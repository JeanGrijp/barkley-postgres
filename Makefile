SHELL := /bin/bash

.PHONY: up connection down queries

up:
	./up.sh

connection:
	./print-connection.sh

down:
	docker-compose down

queries:
	./watch-queries.sh
