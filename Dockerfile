FROM        ubuntu:trusty
RUN         apt-get update
RUN         apt-get install -y reprepro apache2 maven libsaxonb-java wget
ADD         src/reprepro.conf /etc/apache2/sites-available/reprepro.conf
ADD         src/index.html /var/packages/index.html
RUN         a2dissite 000-default
RUN         a2ensite reprepro
ADD         src/distributions /var/packages/debian/conf/distributions
ADD         src/update-repo.sh /update-repo/bin/update-repo.sh
RUN         mkdir -p /update-repo/etc /update-repo/var/log
RUN         touch /update-repo/etc/REPOSITORIES /update-repo/etc/ARTIFACTS /update-repo/var/log/update-repo.log
RUN         chmod +x /update-repo/bin/update-repo.sh
ADD         src/crons.conf /tmp/crons.conf
RUN         crontab /tmp/crons.conf
CMD         service apache2 start && cron && tail -f /update-repo/var/log/update-repo.log
