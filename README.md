# keycloak-nginxproxy

This repository provides complete guide to **Keycloak identity provider** behind nginx reverse proxy together with valid public let's encrypt certificate. As a bonus there is an OIDC test app **book-service** which can be seemlesly integrated with keycloak instance in one docker compose file. This approach was to connect multiple working repositories and technologies together to get a fully working Keycloak as well as to be able to test it right after installation. 

So the components are following (with references to other github respositories):

- Keycloak 23.0.1 (official repo with custom built image)
- Postgres 16.1 with pgadmin 4.5.1 (official image)
- Nginx proxy manager (jc21/nginx-proxy-manager) 2.10.4 --> https://github.com/NginxProxyManager/nginx-proxy-manager/tree/develop
- MongoDB 7.0.2
- Book-service test OIDC client app (book-service:1.0.0) --> https://github.com/ivangfr/springboot-keycloak-mongodb-testcontainers/tree/master


# Keycloak installation

This section describes how to install and maintain keycloak using docker-compose. I used production build with optimized settings which is also ready
for reverse proxy setup using NGINX or other proxy/LB (HA proxy, etc.). This is guide provides single node installation but it can be easily extended to Keycloak cluster setup (tbd).

## Build custom Keycloak image

First docker image has to be build from specified **Dockerfile**. This `Dockerfile` builds a Keycloak image based on the “quay.io/keycloak/keycloak” image. It configures the **Postgres** as database vendor, specifies desired Keycloak features, and runs the necessary “kc.sh build” command to ensure a proper Keycloak setup.
When `Dockerfile` is ready then run following command (x.x.x stands for keycloak version, in this case **23.0.1**):
```
sudo docker build --build-arg KEYCLOAK_VERSION=<x.x.x> -t keycloak --progress=plain --no-cache . 
```

Image be be built also docker compose as a part of ``docker-compose.yml``:
```
sudo docker compose build --build-arg KEYCLOAK_VERSION=<x.x.x> -t keycloak --progress=plain --no-cache . 
```

Before we start Keycloak we need to create ``docker-compose.yml`` file usually in the same directory as ``Dockerfile``. We need to specify ``postgres`` as external database (running in separate container) and ``pgadmin`` as admin interface for postgress. In the next step we will add also ``nginx proxy manager`` so we have full Keycloak setup ready.


## Configure and prepare nginx proxy manager with letsencrypt

You can refer to link below to get more information about **nginx proxy manager** 
https://www.virtualizationhowto.com/2023/10/setting-up-nginx-proxy-manager-on-docker-with-easy-letsencrypt-ssl/

For our purpose we need to add following configuration to our docker compose:
```
app:
    image: 'jc21/nginx-proxy-manager:latest'
    restart: unless-stopped
    ports:
      - '80:80'
      - '81:81'
      - '443:443'
    volumes:
      - ./data:/data
      - ./letsencrypt:/etc/letsencrypt
    networks:
      - local
```
This will create nginx proxy manager together with letsencrypt plugin so we're able to manage both nginx reverse proxy and certificates for our backend keycloak instance (or potentially any other backed instances).

## Final docker compose file for Keycloak and Nginx Proxy Manager

Now we have keycloak image ready so we can create our `docker compose` file. For this example we put all secrets and important variables in local `.env` file which looks like this:

```
POSTGRES_USER="postgres"
POSTGRES_PASSWORD="postgres_db_password"
POSTGRES_DB="db_name"
PGADMIN_DEFAULT_PASSWORD="pgadmin_password"
KEYCLOAK_ADMIN="keycloak_admin_user"
KEYCLOAK_ADMIN_PASSWORD="keycloak_admin_password"
```

> [!IMPORTANT]
> We recommend to set file permissions for `.env` file to a absolute minimum (in our case `sudo chown root:root .env` && `sudo chmod 400 .env`) since `.env` file is not used for production grade systems but unfortunately Keycloak still does not support ``docker secrets``. For production please use docker swarm docker secrets, hashicorp vault or other secret management tool.

Then we can reference `.env` variables in final `docker compose`:
```
version: "3.9"
services:
  postgres:
    container_name: db
    image: "postgres:16.1" #before "postgres:14.4"
    healthcheck:
      test: [ "CMD", "pg_isready", "-q", "-d", "postgres", "-U", "postgr159" ]
      timeout: 45s
      interval: 10s
      retries: 10
    volumes:
      #- postgres_data:/var/lib/postgresql/data --> old path postgres 14
       - postgres_16_data:/var/lib/postgresql/data
      #- ./sql:/docker-entrypoint-initdb.d/:ro # turn it on, if you need run init DB
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_HOST: postgres
    networks:
      - local
    ports:
      - "5432:5432"

  pgadmin:
    container_name: pgadmin
    image: "dpage/pgadmin4:5.1"
    environment:
      PGADMIN_DEFAULT_EMAIL: postgres@site.local
      PGADMIN_DEFAULT_PASSWORD: ${PGADMIN_DEFAULT_PASSWORD}
    ports:
      - "5050:80"
    networks:
      - local

  keycloak:
    container_name: keycloak
    build:
      context: .
      args:
        KEYCLOAK_VERSION: 23.0.1 #specify keycloak image version from docker build
    command: ['start', '--optimized']
    depends_on:
      - "postgres"
    environment:
      JAVA_OPTS_APPEND: -Dkeycloak.profile.feature.upload_scripts=enabled
      KC_DB_PASSWORD: ${POSTGRES_PASSWORD} #/run/secrets/pg_pass
      KC_DB_URL: jdbc:postgresql://postgres/kckdb
      KC_DB_USERNAME: ${POSTGRES_USER}
      KC_HEALTH_ENABLED: 'true'
      KC_HTTP_ENABLED: 'true'
      KC_METRICS_ENABLED: 'true'
      KC_HOSTNAME: example.domain.com 
      #KC_HOSTNAME_ADMIN_URL: http://<yourdomain>:8180/ --> you can specify if you use different host for admin interface, can be internal or external domain.
      # KC_HOSTNAME_PORT: 8180  --> you can specify if you run only local keycloak instance, our instance runs behind nginx proxy and is accessible via https
      #KC_HOSTNAME_URL: http://keycloak.domain.local:8180 --> you can also speficy Keycloak HOSTNAME URL instead of KC_HOSTNAME to be more explicit
      KC_PROXY: edge --> keycloak will be running behind proxy, alternative is reencrypt where also keycloak is running on https behind proxy
      KEYCLOAK_ADMIN: ${KEYCLOAK_ADMIN}
      KEYCLOAK_ADMIN_PASSWORD: ${KEYCLOAK_ADMIN_PASSWORD} #/run/secrets/kck_admin
    ports:
      - "8180:8080"
      - "8787:8787" # debug port
    networks:
      - local

  app:
    image: 'jc21/nginx-proxy-manager:latest'
    restart: unless-stopped
    ports:
      - '80:80'
      - '81:81'
      - '443:443'
    volumes:
      - ./data:/data
      - ./letsencrypt:/etc/letsencrypt
    networks:
      - local
  
networks:
  local:
    name: local
    driver: bridge

volumes:
  postgres_16_data:
```

Now we start our docker compose stack for Keycloak + Postgress + NGINX PROXY Manager:
```
sudo docker compose up -d
```
Clarify if all necesarry containers are running:
```
sudo docker ps 

IMAGE                             
   keycloak-keycloak                           
   postgres:16.1                       
   jc21/nginx-proxy-manager:latest
   dpage/pgadmin4:5.1     
```
Now you can test if Keycloak is running at `curl -i http://local_ip:8080/` since port `8080` is default and reachable via internal network. Next part configures and installs letsencrypt certificate so our Keycloak instance will be available and trusted from public internet.  

## Install letsencrypt certificate via API
In order to finish the installation we need to request letsencrypt certificate for our public domain ``domain.example.com`` that we specified in docker compose as ``KC_HOSTNAME`` variable. 

1) Check if NGINX proxy is URL is available ```curl -i http://localhost:81/``` (or use your internal IP)

2) Login via browser and refer to **Section 2** at https://www.virtualizationhowto.com/2023/10/setting-up-nginx-proxy-manager-on-docker-with-easy-letsencrypt-ssl/ and setup NGINX PROXY MANAGER admin account (we need it to generate API calls to NGINX).

3) Once this is ready open ``scripts/nginx_proxy_cert.sh`` and set following variables:

```
IDENTITY="<your_nginx_admin>"
NGINX_PASSWORD="<your_nginx_admin_password>"
NGINX_HOST="localhost/internal_IP"
NGINX_PORT="81"
DOMAIN_NAMES="<yourdomain.example.com>"
FORWARD_HOST="<internal_ip_keycloak_instance>"
FORWARD_PORT="<internal_keycloak_port(default 8080)>"
EMAIL="<your_valid_email_address_for_public_domain>" 
```
Then run ``nginx_proxy_cert.sh``. Script first gathers ``access token`` via NGINX PROXY MANAGER API and then creates ``nginx proxy`` host and configures proxy location which is in our case our Keycloak host at ``http://x.x.x.x:8080/`` (replace x.x.x.x by your internal IP)

4) Verify if host was created either by `curl -i https://domain.example.com` or check via NGINX PROXY web GUI.

5) If you don't want to do it via script and API, you can also do it via NGINX PROXY GUI (example in link above STEP 4).

## Keycloak recap
Now we have fresh Keycloak instance installed, with admin account and default ``MASTER`` realm in place. Navigate to ```https://domain.example.com``` choose ``Administration Console`` and it should redirect you to ```https://domain.example.com/admin/ ```. Login with Keycloak admin account (I recommend to setup 2FA) and verify if it's working.


### Maintenance and operations

```
sudo docker compose down
sudo docker compose logs
sudo docker inspect <container_id>
sudo docker compose ps
```


# TEST OIDC client app with keycloak
This step is additional if you want to test OpenID connect application with your existing Keycloak instance. The following steps will include:
1) Configuring Keycloak client for OIDC (assuming that we have Keycloak instance already up an running)
2) Setting up test app `book-service` running in docker-compose (the same as Keycloak)
3) Test if all works as expected

## Prepare keycloak OIDC client app (book-service)
1) Clone https://github.com/ivangfr/springboot-keycloak-mongodb-testcontainers.git 
2) From the you can either use **./init-keycloak.sh** script or configure client manaully as shown in https://github.com/ivangfr/springboot-keycloak-mongodb-testcontainers/tree/master#using-keycloak-website
Follow the steps decrbed below.

### Using Keycloak Website

You can configure `CLIENT APP `and `USER` step by step via GUI. Follow the steps below.

#### Login

- Access https://domain.example.com/admin

- Login with the credentials (you set during keycloak installation)
  ```
  Username: xxxx
  Password: xxxx
  ```

#### Create a new Realm

- On the left menu, click the dropdown button that contains `Master` and then, click `Create Realm` button
- Set `company-services` to the `Realm name` field and click `Create` button

#### Create a new Client

- On the left menu, click `Clients`
- Click `Create client` button
- In `General Settings`
  - Set `book-service` to `Client ID`
  - Click `Next` button
- In `Capability config`
  - Enable `Client authentication` toggle switch
  - Click `Save` button
- In `Settings` tab
  - Set `http://localhost:9080/*` to `Valid Redirect URIs`
  - Click `Save` button
- In `Credentials` tab, you can find the secret generated for `book-service`
- In `Roles` tab
  - Click `Create Role` button
  - Set `manage_books` to `Role Name`
  - Click `Save` button

#### Create a new User

- On the left menu, click `Users`
- Click `Create new user` button
- Set `testuser` to `Username` field
- Click `Save`
- In `Credentials` tab
  - Click `Set password` button
  - Set the value `youruserpassowrd` to `Password` and `Password confirmation`
  - Disable the `Temporary` field toggle switch
  - Click `Save` button
  - Confirm by clicking `Save Password` button
- In `Role Mappings` tab
  - Click `Assign role` button
  - Click `Filter by Origin` dropdown button and select `book-service`
  - Select `manage_books` role and click `Assign` button


## build springboot-keycloak-mongodb app and setup OIDC with keycloak 
1) cd to `springboot-keycloak-mongodb-testcontainers` directory
2) Install prerequisities in your environment (will be needed to build `book-service` image): 
-  Java JDK 17 or higher (used in our example also openjdk can be used) - should be working also with newer java. For java17 installation refer to https://www.rosehosting.com/blog/how-to-install-java-17-lts-on-ubuntu-20-04/ 

-  jq
-  gradle 8.3 --> https://gradle.org/install/

3) Change **issuer-uri**: explictitly in following files
- `~/springboot-keycloak-mongodb-testcontainers/book-service/main/resoruces/application.yml` 
- `~/springboot-keycloak-mongodb-testcontainers/book-service/build/resources/main/application.yml`
by setting your host, since default config expects keycloak to run on port 8080.
```
FROM: issuer-uri: http://${KEYCLOAK_HOST:localhost}:${KEYCLOAK_PORT:8080}/realms/company-services
TO: issuer-uri: issuer-uri: https://${KEYCLOAK_HOST}/realms/company-services
```
The values `$KEYCLOAK_HOST `and `$KEYCLOAK_PORT` should be taken as environment variables during build and are hardcoded into application (but it was not working in my case).  

4) run docker-build.sh to prepare book-service docker image
5) check if docker image was built - run **sudo docker images** and it should show **ivanfranchin/book-service**
6) Update overall keycloak docker compose by adding mongo DB and book-service containers

**mongo db and book-service:**
```
mongodb:
    image: mongo:7.0.2
    container_name: mongodb
    ports:
      - "27017:27017"
    healthcheck:
      test: echo 'db.stats().ok' | mongosh localhost:27017/bookdb --quiet
    networks: 
      - local

book-service:
    image: ivanfranchin/book-service:1.0.0
    container_name: book-service
    ports:
      - "9080:8080"
    environment:
      MONGODB_HOST: mongodb
      #KEYCLOAK_HOST: domain.example.com 
      #KEYCLOAK_PORT: 443
    networks:
      - local
```
You can skip defining `$KEYCLOAK_PORT` variable since changed configuration file `STEP 3` as we use keycloak at https on public domain (you can however set according to your preference). This step is important if you want correctly point `book-service` app to keycloak instance.

7) Containers should be in the same docker network as your keycloak instance, but you can create and use separate docker compose for running book-service with mongodb as stantalone app
8) for newly created docker compose run (mongo db and book-service will run, rest will stay untouched):  
```
docker compose up -d
```
9) test if book service app is running (you can replace X.X.X.X either by localhost or internal IP address of your running instance) - you should get HTTP 200 OK
```
curl -i http://X.X.X.X:9080/api/books  #should return HTTP 200
```

10) In the next step we test `book-service` if app works with created OIDC credentials.

11) Export client secret from Keycloak as environment variable (for client ID book-service):
```
BOOK_SERVICE_CLIENT_SECRET=............... 
```
12) Open `scripts/keycloak-gettoken.sh` and set following variables which are needed to gather **ACCESS TOKEN** needed to access book-service app.

```
KEYCLOAK_HOST_PORT=${2:-"<domain.example.com>"}
USER=${3:-"<your_keycloak_user>"}
PASSWORD=${4:-"<your_keycloak_password>"}
```
then run
```
./keycloak-gettoken.sh "$BOOK_SERVICE_CLIENT_SECRET"
```
The script will export access token gathered from Keycloak to variable `$ACCESS_TOKEN`.

13) Test book-service API without access_token with **POST to /api/books**

```
curl -i -X POST http://localhost:9080/api/books \
  -H "Content-Type: application/json" \
  -d '{"authorName": "Ivan Franchin", "title": "Java 8", "price": 10.5}' 
  ```
You should get HTTP 401 (unauthorized).

14) Test using provided OIDC **ACCESS_TOKEN**

```
curl -i -X POST http://localhost:9080/api/books \
  -H "Authorization: Bearer "$ACCESS_TOKEN"" \
  -H "Content-Type: application/json" \
  -d '{"authorName": "Ivan Franchin", "title": "Java 8", "price": 10.5}'
```
and it should return HTTP 201 together with following data:
```
{"id":"658363618e30d11dcd8cb2b2","authorName":"Ivan Franchin","title":"Java 8","price":10.5}
```