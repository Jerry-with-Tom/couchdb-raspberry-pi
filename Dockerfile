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

# 应用补丁修复 armv7 编译错误
RUN printf '%s\n' '--- a/src/couch/priv/couch_cfile/couch_cfile.c' \
    '+++ b/src/couch/priv/couch_cfile/couch_cfile.c' \
    '@@ -366,9 +366,9 @@ static int pread_nif(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])' \
    '     if (argc != 3)' \
    '         return enif_make_badarg(env);' \
    ' ' \
    '-    long offset, block_size;' \
    '+    ErlNifSInt64 offset, block_size;' \
    ' ' \
    '     if (!enif_get_int64(env, argv[1], &offset)' \
    '         || !enif_get_int64(env, argv[2], &block_size))' \
    '@@ -388,7 +388,7 @@ static int pwrite_nif(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])' \
    '     if (argc != 4)' \
    '         return enif_make_badarg(env);' \
    ' ' \
    '-    long result, offset;' \
    '+    long result; ErlNifSInt64 offset;' \
    ' ' \
    '     char *buf;' \
    '     int flags;' > /tmp/couch_cfile.patch \
    && cd /couchdb && patch -p1 < /tmp/couch_cfile.patch

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
