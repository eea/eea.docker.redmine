all: build

build:
	@docker build --no-cache=true --tag=eeacms/redmine .
