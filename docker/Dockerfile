FROM maven:3-jdk-8

# --no-install-recommends
RUN apt-get update && apt-get install -y build-essential ant makedev locales build-essential g++ nano procps xvfb iproute net-tools iputils-ping curl wget rsync libxrender-dev libxtst-dev check pkg-config valgrind libxslt-dev libxml2-dev libreadline6 libreadline6-dev curl git-core zlib1g zlib1g-dev libssl-dev libyaml-dev libsqlite3-dev sqlite3 libxml2-dev libxslt-dev autoconf libc6-dev libgdbm-dev ncurses-dev automake libtool bison subversion libffi-dev openssl libxrender-dev libxtst-dev xmlstarlet python3.4 python2.7 python-pip python-virtualenv && rm -rf /var/lib/apt/lists/*

RUN useradd -g users user && mkdir -p /home/user && chown -R user:users /home/user
WORKDIR /app

RUN chown -R user:users /app
USER user

CMD ["/bin/sleep", "360000"]
