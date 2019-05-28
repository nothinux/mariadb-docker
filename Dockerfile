FROM ubuntu:bionic

RUN groupadd -r mysql && useradd -r -g mysql mysql

RUN set -ex; \
	apt-get update; \
	if ! which gpg; then \
		apt-get install -y --no-install-recommends gnupg; \
	fi; \
	if ! gpg --version | grep -q '^gpg (GnuPG) 1\.'; then \
		 apt-get install -y --no-install-recommends dirmngr; \
	fi; \
	rm -rf /var/lib/apt/lists/*

ENV GOSU_VERSION 1.10
RUN set -ex; \
	\
	fetchDeps=' \
		ca-certificates \
		wget \
	'; \
	apt-get update; \
	apt-get install -y --no-install-recommends $fetchDeps; \
	rm -rf /var/lib/apt/lists/*; \
	\
	dpkgArch="$(dpkg --print-architecture | awk -F- '{ print $NF }')"; \
	wget -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch"; \
	wget -O /usr/local/bin/gosu.asc "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch.asc"; \
	\
	export GNUPGHOME="$(mktemp -d)"; \
	gpg --batch --keyserver ha.pool.sks-keyservers.net --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4; \
	gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu; \
	command -v gpgconf > /dev/null && gpgconf --kill all || :; \
	rm -r "$GNUPGHOME" /usr/local/bin/gosu.asc; \
	\
	chmod +x /usr/local/bin/gosu; \
	
    gosu nobody true; \
	\
	apt-get purge -y --auto-remove $fetchDeps

RUN mkdir /docker-entrypoint-initdb.d

RUN apt-get update && apt-get install -y --no-install-recommends \
		apt-transport-https ca-certificates \
		pwgen \
		tzdata \
	&& rm -rf /var/lib/apt/lists/*

ENV GPG_KEYS \
	199369E5404BD5FC7D2FE43BCBCB082A1BB943DB \
	177F4010FE56CA3336300305F1656F24C74CD1D8 \
	430BDF5C56E7C94E848EE60C1C4CBDCDCD2EFD2A \
	4D1BB29D63D98E422B2113B19334A25F8507EFA5
RUN set -ex; \
	export GNUPGHOME="$(mktemp -d)"; \
	for key in $GPG_KEYS; do \
		gpg --batch --keyserver ha.pool.sks-keyservers.net --recv-keys "$key"; \
	done; \
	gpg --batch --export $GPG_KEYS > /etc/apt/trusted.gpg.d/mariadb.gpg; \
	command -v gpgconf > /dev/null && gpgconf --kill all || :; \
	rm -r "$GNUPGHOME"; \
	apt-key list

ENV MARIADB_MAJOR 10.1
ENV MARIADB_VERSION 1:10.1.40+maria-1~bionic

RUN set -e;\
	echo "deb http://ftp.osuosl.org/pub/mariadb/repo/$MARIADB_MAJOR/ubuntu bionic main" > /etc/apt/sources.list.d/mariadb.list; \
	{ \
		echo 'Package: *'; \
		echo 'Pin: release o=MariaDB'; \
		echo 'Pin-Priority: 999'; \
	} > /etc/apt/preferences.d/mariadb

RUN set -ex; \
	{ \
		echo "mariadb-server-$MARIADB_MAJOR" mysql-server/root_password password 'unused'; \
		echo "mariadb-server-$MARIADB_MAJOR" mysql-server/root_password_again password 'unused'; \
	} | debconf-set-selections; \
	backupPackage='mariadb-backup-10.1'; \
	apt-get update; \
	apt-get install -y \
		"mariadb-server=$MARIADB_VERSION" \
		$backupPackage \
		socat \
	; \
	rm -rf /var/lib/apt/lists/*; \
	sed -ri 's/^user\s/#&/' /etc/mysql/my.cnf /etc/mysql/conf.d/*; \
	rm -rf /var/lib/mysql; \
	mkdir -p /var/lib/mysql /var/run/mysqld; \
	chown -R mysql:mysql /var/lib/mysql /var/run/mysqld; \
	chmod 777 /var/run/mysqld; \
	find /etc/mysql/ -name '*.cnf' -print0 \
		| xargs -0 grep -lZE '^(bind-address|log)' \
		| xargs -rt -0 sed -Ei 's/^(bind-address|log)/#&/'; \
	echo '[mysqld]\nskip-host-cache\nskip-name-resolve' > /etc/mysql/conf.d/docker.cnf

VOLUME /var/lib/mysql

COPY docker-entrypoint.sh /usr/local/bin/
RUN ln -s usr/local/bin/docker-entrypoint.sh / # backwards compat
ENTRYPOINT ["docker-entrypoint.sh"]

EXPOSE 3306
CMD ["mysqld"]
