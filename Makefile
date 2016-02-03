all: build

build:
	@docker build --tag=eeacms/redmine .
