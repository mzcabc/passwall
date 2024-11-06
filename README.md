```shell
apt update
apt install docker.io docker-compose

git clone https://github.com/mzcabc/passwall.git

cd passwall

mv .env.sample .env

# edit .env

docker-compose up -d
```