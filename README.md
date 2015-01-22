# [reprepro-service](https://github.com/snaekobbi/reprepro-service)

Docker container running a Reprepro service (Debian repository). A
script that downloads new DEB files from Maven repositories and adds
them to the Debian repository is executed periodically.

## Building and running the service

To build the image:

    make

To test the service:

    make check

The service must be configured through the `REPOSITORIES` and
`ARTIFACTS` files in `/update-repo/etc`. This could be done by using
the image as a base and ADD'ing your configuration files, or by
mounting a host directory with your configuration files as a data
volume:

    docker run -d -v <path-to-your-etc>:/update-repo/etc snaekobbi/reprepro-service

To expose the service to the host:

    docker run -d -p 80:80 snaekobbi/reprepro-service

To expose the service to another container:

    docker run -d -e 80 --name reprepro snaekobbi/reprepro-service
    docker run --link reprepro:reprepro <some-other-image>

## Using the service

Add the repository to your Apt sources in a file `/etc/apt/sources.list.d/reprepro.list`:

    deb     http://localhost/debian testing main contrib non-free
    deb-src http://localhost/debian testing main contrib non-free

Then update the list of packages:

    sudo apt-get update
