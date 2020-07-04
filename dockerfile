
FROM ubuntu:18.04

#Update en Upgrade to latest version
RUN apt update && apt upgrade -y

#Install required files
RUN DEBIAN_FRONTEND="noninteractive"  apt install curl libunwind8 gettext wget nano docker.io docker-compose -y
RUN apt-get install -y --no-install-recommends ca-certificates curl jq git iputils-ping libcurl4 libicu60 libunwind8 netcat

#Set working directory to /azp
WORKDIR /azp

#Copy start script file and make it executable
COPY ./start.sh .
RUN chmod +x start.sh

#Tell docker to start 'start.sh'
CMD ["./start.sh"]