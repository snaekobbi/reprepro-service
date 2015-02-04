#!/usr/bin/env make -f

DOCKER := docker
TAG := snaekobbi/reprepro-service

all : image

.PHONY: image check

image : Dockerfile
	$(DOCKER) build -t $(TAG) .

check : image
	id=$$(uuidgen|tr A-Z a-z) && \
	    $(DOCKER) build -t $${id} "https://github.com/snaekobbi/nexus-service.git" && \
	    $(DOCKER) run -d \
	                  -e 8081 \
	                  --cidfile test/nexus.cid \
	                  $${id}
	sleep 10
	id=$$(uuidgen|tr A-Z a-z) && \
	    $(DOCKER) build -t $${id} test/build && \
	    $(DOCKER) run -d \
	                  -v $(CURDIR)/test/build/repository:/root/.m2/repository \
	                  --link $$(cat test/nexus.cid | xargs docker inspect --format='{{.Name}}'):nexus \
	                  --cidfile test/build.cid \
	                  $${id} \
	                  bash -c "trap exit TERM; tail -f & wait"
	rm -rf test/pool test/var
	mkdir -p test/var/log
	touch test/var/log/update-repo.log
	$(DOCKER) run -d \
	              -e 80 \
	              -v $(CURDIR)/test/var:/update-repo/var \
	              -v $(CURDIR)/test/etc:/update-repo/etc \
	              -v $(CURDIR)/test/pool:/var/packages/debian/pool \
	              -v $(CURDIR)/test/repository:/root/.m2/repository \
	              --link $$(cat test/nexus.cid | xargs docker inspect --format='{{.Name}}'):nexus \
	              --cidfile test/reprepro.cid \
	              $(TAG) \
	              bash -c "service apache2 start; trap exit TERM; tail -f & wait"
	id=$$(uuidgen|tr A-Z a-z) && \
	    $(DOCKER) build -t $${id} test/install && \
	    $(DOCKER) run -d \
	                  --link $$(cat test/reprepro.cid | xargs docker inspect --format='{{.Name}}'):reprepro \
	                  --cidfile test/install.cid \
	                  $${id} \
	                  bash -c "trap exit TERM; tail -f & wait"
	$(DOCKER) exec $$(cat test/build.cid) mvn deploy -f /tmp/hello-world/pom.xml
	sleep 3
	$(DOCKER) exec $$(cat test/reprepro.cid) /update-repo/bin/update-repo.sh
	sleep 3
	$(DOCKER) exec $$(cat test/install.cid) bash -c "apt-get update; apt-get install -y --force-yes hello-world"
	$(DOCKER) exec $$(cat test/reprepro.cid) /update-repo/bin/update-repo.sh
	sleep 3
	$(DOCKER) exec $$(cat test/install.cid) apt-get update
	test $$( $(DOCKER) exec $$(cat test/install.cid) bash -c \
	    "apt-cache policy hello-world | sed -n 's/^ *\(Installed\|Candidate\): *//p' | uniq" | wc -l ) = 1
	$(DOCKER) exec $$(cat test/build.cid) mvn deploy -f /tmp/hello-world/pom.xml
	sleep 3
	$(DOCKER) exec $$(cat test/reprepro.cid) /update-repo/bin/update-repo.sh
	sleep 3
	$(DOCKER) exec $$(cat test/install.cid) apt-get update
	test $$( $(DOCKER) exec $$(cat test/install.cid) bash -c \
	    "apt-cache policy hello-world | sed -n 's/^ *\(Installed\|Candidate\): *//p' | uniq" | wc -l ) = 2
	$(DOCKER) exec $$(cat test/install.cid) apt-get install -y --force-yes hello-world
	$(DOCKER) stop $$(paste test/*.cid)
	$(DOCKER) rm $$(paste test/*.cid)
	rm test/*.cid
