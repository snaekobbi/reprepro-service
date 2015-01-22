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
	    $(DOCKER) run -v $(CURDIR)/test/build/repository:/root/.m2/repository \
	                  --rm \
	                  --link $$(cat test/nexus.cid | xargs docker inspect --format='{{.Name}}'):nexus \
	                  $${id} \
	                  /bin/bash -c "mvn deploy -f /tmp/hello-world/pom.xml"
	rm -rf test/pool test/var
	$(DOCKER) run -d \
	              -e 80 \
	              -v $(CURDIR)/test/var:/update-repo/var \
	              -v $(CURDIR)/test/etc:/update-repo/etc \
	              -v $(CURDIR)/test/pool:/var/packages/debian/pool \
	              -v $(CURDIR)/test/repository:/root/.m2/repository \
	              --link $$(cat test/nexus.cid | xargs docker inspect --format='{{.Name}}'):nexus \
	              --name reprepro \
	              $(TAG)
	$(DOCKER) exec reprepro /update-repo/bin/update-repo.sh
	id=$$(uuidgen|tr A-Z a-z) && \
	    $(DOCKER) build -t $${id} test/install && \
	    $(DOCKER) run --rm \
	                  --link reprepro:reprepro \
	                  $${id} \
	                  /bin/bash -c "apt-get update && apt-get install -y --force-yes hello-world"
	$(DOCKER) stop reprepro $$(cat test/nexus.cid)
	$(DOCKER) rm reprepro $$(cat test/nexus.cid)
	rm test/nexus.cid
