FROM debian:bookworm-slim AS builder

ENV COUCHDB_VERSION=3.5.0
ENV NODEVERSION=22


# Prepare build env
RUN apt-get update && apt-get install -y git
RUN git clone --depth 1 https://github.com/apache/couchdb-ci.git
# For couchdb-ci compatability
RUN adduser jenkins
RUN bash /couchdb-ci/bin/install-dependencies.sh
RUN apt-get install -y libmozjs-78-dev

# Build CouchDB
WORKDIR /
RUN git clone --depth 1 --branch $COUCHDB_VERSION https://github.com/apache/couchdb.git 
WORKDIR /couchdb
RUN ./configure --disable-docs --spidermonkey-version 78
# workaround chromedriver not supporting armv7
RUN sed -i 's/npm install/npm uninstall chromedriver \&\& npm install/g' Makefile 

# Fix 32-bit (arm/v7) compilation: long is 4 bytes but ErlNifSInt64 is 8 bytes
RUN sed -i 's/static long efile_preadv(int fd, long offset/static long efile_preadv(int fd, off_t offset/' \
        /couchdb/src/couch/priv/couch_cfile/couch_cfile.c && \
    sed -i 's/unsigned long bytes_read;/size_t bytes_read;/' \
        /couchdb/src/couch/priv/couch_cfile/couch_cfile.c && \
    sed -i '/^static long efile_preadv/,/^}/{ s/long result;/ssize_t result;/; }' \
        /couchdb/src/couch/priv/couch_cfile/couch_cfile.c && \
    sed -i 's/long bytes_written;/ssize_t bytes_written;/g' \
        /couchdb/src/couch/priv/couch_cfile/couch_cfile.c && \
    sed -i 's/long offset, block_size, bytes_read;/ErlNifSInt64 offset, block_size; ssize_t bytes_read;/' \
        /couchdb/src/couch/priv/couch_cfile/couch_cfile.c && \
    sed -i 's/long result, offset;/ssize_t result; ErlNifSInt64 offset;/' \
        /couchdb/src/couch/priv/couch_cfile/couch_cfile.c && \
    grep -n "ErlNifSInt64\|off_t offset\|size_t bytes_read\|ssize_t result\|ssize_t bytes_written" \
        /couchdb/src/couch/priv/couch_cfile/couch_cfile.c

RUN make release

FROM debian:bookworm-slim

COPY --from=builder /couchdb/rel/couchdb /opt/couchdb
COPY --chown=couchdb:couchdb 10-docker-default.ini /opt/couchdb/etc/default.d/
COPY --chown=couchdb:couchdb vm.args /opt/couchdb/etc/
COPY docker-entrypoint.sh /usr/local/bin

RUN groupadd -g 5984 -r couchdb && useradd -u 5984 -d /opt/couchdb -g couchdb couchdb; \
    chown -R couchdb:couchdb /opt/couchdb; \
    find /opt/couchdb -type d -exec chmod 0770 {}; \
    chmod 0644 /opt/couchdb/etc/*; \
    chmod +x /usr/local/bin/docker-entrypoint.sh

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends tini erlang-nox libicu72 libmozjs-78-dev; \
    rm -rf /var/lib/apt/lists/*; \
    tini --version

RUN ln -s usr/local/bin/docker-entrypoint.sh /docker-entrypoint.sh # backwards compat
ENTRYPOINT ["tini", "--", "/docker-entrypoint.sh"]

VOLUME /opt/couchdb/data

# 5984: Main CouchDB endpoint
# 4369: Erlang portmap daemon (epmd)
# 9100: CouchDB cluster communication port
EXPOSE 5984 4369 9100
CMD ["/opt/couchdb/bin/couchdb"]
