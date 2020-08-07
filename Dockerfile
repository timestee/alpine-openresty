FROM alpine:latest

RUN ln -sf /usr/share/zoneinfo/Asia/Shanghai  /etc/localtime

LABEL SERVICE_NAME="nginx"

HEALTHCHECK CMD docker-healthcheck

# Docker Build Arguments
ARG RESTY_VERSION="1.11.2.3"
ARG RESTY_LUAROCKS_VERSION="2.4.2"
ARG RESTY_OPENSSL_VERSION="1.0.2l"
ARG RESTY_PCRE_VERSION="8.40"
ARG RESTY_J="1"
ARG RESTY_NPS_VERSION="1.12.34.2"
ARG RESTY_CONFIG_OPTIONS="\
    --prefix=/usr/share \
    --conf-path=/etc/nginx/nginx.conf \
    --sbin-path=/usr/sbin/nginx \
    --error-log-path=/var/log/nginx/error.log \
    --http-log-path=/var/log/nginx/access.log \
    --pid-path=/var/run/nginx.pid \
    --lock-path=/var/run/nginx.lock \
    --http-client-body-temp-path=/var/cache/nginx/client_temp \
    --http-proxy-temp-path=/var/cache/nginx/proxy_temp \
    --http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
    --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
    --http-scgi-temp-path=/var/cache/nginx/scgi_temp \
    --with-file-aio \
    --with-http_addition_module \
    --with-http_auth_request_module \
    --with-http_gunzip_module \
    --with-http_gzip_static_module \
    --with-http_image_filter_module=dynamic \
    --with-http_realip_module \
    --with-http_secure_link_module \
    --with-http_slice_module \
    --with-http_ssl_module \
    --with-http_stub_status_module \
    --with-http_sub_module \
    --with-http_v2_module \
    --with-ipv6 \
    --with-md5-asm \
    --with-pcre-jit \
    --with-sha1-asm \
    --with-stream \
    --with-stream_ssl_module \
    --with-threads \
    --without-http_redis2_module \
    --without-http_redis_module \
    --without-http_rds_csv_module \
    --without-http_rds_json_module \
    "

# These are not intended to be user-specified
ARG _RESTY_CONFIG_DEPS="--with-openssl=/tmp/openssl-${RESTY_OPENSSL_VERSION} --with-pcre=/tmp/pcre-${RESTY_PCRE_VERSION}"


ENV PCRE_CONF_OPT="--enable-utf8 --enable-unicode-properties"

# 1) Install apk dependencies
# 2) Download and untar OpenSSL, PCRE, and OpenResty
# 3) Build OpenResty
# 4) Cleanup

RUN \
    apk add --no-cache --update --virtual .build-deps \
        build-base \
        git \
        gd-dev \
        libxslt-dev \
        linux-headers \
        cmake \
        make \
        perl-dev \
        readline-dev \
        zlib-dev \
        libmaxminddb-dev \
    && apk add --no-cache --update \
        curl \
        jq \
        gd \
        libgcc \
        libxslt \
        zlib \
        libmaxminddb \
    && cd /tmp \
    && curl -fSL https://www.openssl.org/source/openssl-${RESTY_OPENSSL_VERSION}.tar.gz | tar -zx \
    \
    && curl -fSL https://ftp.pcre.org/pub/pcre/pcre-${RESTY_PCRE_VERSION}.tar.gz | tar -zx \
    \
    && curl -fSL https://openresty.org/download/openresty-${RESTY_VERSION}.tar.gz | tar -zx \
    && cd /tmp/openresty-${RESTY_VERSION} \
    && ./configure -j${RESTY_J} ${_RESTY_CONFIG_DEPS} ${RESTY_CONFIG_OPTIONS} \
    && make -j${RESTY_J} \
    && make -j${RESTY_J} install \
    && cd /tmp \
    && curl -fSL http://luarocks.github.io/luarocks/releases/luarocks-${RESTY_LUAROCKS_VERSION}.tar.gz | tar -zx \
    && cd luarocks-${RESTY_LUAROCKS_VERSION} \
    && ./configure \
        --prefix=/usr/share/luajit \
        --with-lua=/usr/share/luajit \
        --lua-suffix=jit-2.1.0-beta2 \
        --with-lua-include=/usr/share/luajit/include/luajit-2.1 \
    && make build \
    && make install \
    && ln -s /usr/share/luajit/bin/luarocks /bin/luarocks \
    && cd /tmp \
    \
    && ln -sf /dev/stdout /var/log/nginx/access.log \
    && ln -sf /dev/stderr /var/log/nginx/error.log \
    && git clone https://github.com/DaveGamble/cJSON \
    && cd cJSON && cmake . && make && make install && cd .. \
    \
    && mkdir -p /var/cache/nginx /etc/nginx/sites-enabled /etc/nginx/upstream-conf.d /etc/nginx/templates \
    \
    && apk del .build-deps \
    && rm -rf /tmp/* \
    && rm -f /etc/nginx/conf.d/default.conf

RUN \
    apk add --no-cache --update --virtual .build-deps \
        build-base \
        git \
        cmake \
        make \
    \
    && luarocks install lua-resty-libcjson \
    && sed -ie 's#ffi_load "cjson"#ffi_load "/usr/local/lib/libcjson.so"#' /usr/share/luajit/share/lua/5.1/resty/libcjson.lua \
    && luarocks install lua-resty-http \
    && luarocks install statsd \
    && luarocks install lua-resty-statsd \
    && luarocks install lua-resty-beanstalkd \
    && luarocks install lua-resty-jit-uuid \
    && luarocks install lua-resty-cookie \
    \
    && apk del .build-deps

RUN find /usr/local/bin -type f -exec chmod +x {} \;

CMD ["nginx"]