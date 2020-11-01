##############################################################
# Makefile for building and testing
##############################################################

# Run make SKIP_TEST=y
SKIP_TESTS:=

# Version vars
VERSION:=1.0.$(shell git rev-list HEAD | wc -l)
MUNICIPALPERMITCHABOT_JAR=MunicipalPermitChabot-1.0.0.jar

# Docker vars
APP_NAME=municipal-permit-chabot.app
APP_TAG=$(VERSION)
APP_IMG=$(APP_NAME):$(APP_TAG)
REMOTE_IMG:=docker.io/umgccaps/$(APP_IMG)
BUILD_IMG=docker.io/umgccaps/advance-development-factory:latest
BRANCH=$(shell git rev-parse --abbrev-ref HEAD)

# Maven options
MAVEN_OPTS:=-Dversion=$(VERSION)

BUILD_ARGS=--build-arg MAPQUEST_APIKEY=$(MAPQUEST_APIKEY)
BUILD_ARGS+=--build-arg DB_USER=$(DB_USER)
BUILD_ARGS+=--build-arg DB_PASS="${DB_PASS}"
BUILD_ARGS+=--build-arg DB_URL=$(DB_URL)
BUILD_ARGS+=--build-arg ADDRESS_CITY=$(ADDRESS_CITY)
BUILD_ARGS+=--build-arg ADDRESS_STATE=$(ADDRESS_STATE)
BUILD_ARGS+=--build-arg VERSION=$(VERSION)
BUILD_ARGS+=--build-arg MUNICIPALPERMITCHABOT_APP=$(MUNICIPALPERMITCHABOT_JAR)

URL=umgc-chatbot

# Skip test flag
# make all SKIP_TESTS=y <- doest not run unit tests
ifdef SKIP_TESTS
	MAVEN_OPTS:=$(MAVEN_OPTS) -Dmaven.test.skip=true
endif

export VERSION

# PHONY
.PHONY: all image start clean push sonar

##############################################################
#	make all:
#		This recipe starts the municipal-permit-chabot-build-env with repo volumed
#		mapped into the container can creates the municipal-permit-chabot-app jar
#		then exits. This is useful so that developer do not 
#		need to modify environments.
#
##############################################################
all:
	docker run -v $(PWD)/:/repo --entrypoint '/bin/bash' $(BUILD_IMG) \
		-c 'cd /repo && make target/$(MUNICIPALPERMITCHABOT_JAR) VERSION=$(VERSION)'

# This internal recipe is used by build to create the municipal-permit-chabot versioned jar
target/$(MUNICIPALPERMITCHABOT_JAR):	
	mvn $(MAVEN_OPTS) package -f pom.xml

##############################################################
#	make image:
#		This recipe create the project-tracker Docker image
#
##############################################################
image: target/$(MUNICIPALPERMITCHABOT_JAR)
	cp target/$(MUNICIPALPERMITCHABOT_JAR) ./$(MUNICIPALPERMITCHABOT_JAR)
	docker build -f ./docker/Dockerfile $(BUILD_ARGS) -t $(APP_IMG) .
	rm -rf ./$(MUNICIPALPERMITCHABOT_JAR)

sonar:
	docker run -v $(PWD)/:/repo --entrypoint '/bin/bash' $(BUILD_IMG) \
		-c 'cd /repo &&	mvn verify sonar:sonar -Dsonar.branch.name=$(BRANCH)'
		
##############################################################
#	make start:
#		This recipe start the project-tracker Docker app
#
##############################################################
start:
	docker-compose -f docker/docker-compose.yml  up 


##############################################################
#	make clean:
#		This recipe cleans the user workspace
#
##############################################################
clean:
	@mvn $(MAVEN_OPTS) clean -f pom.xml

##############################################################
#	make push:
#		This recipe pushes the Docker vlol application to the
#		Azure container registry 
#
##############################################################
push:
	docker tag $(APP_IMG) $(REMOTE_IMG)
	docker push $(REMOTE_IMG)

##############################################################
#	make deploy:
#		This deploys a given chatbot application to an Azure 
#		container instances. This need to be done within the
#		build-env Docker container unless user have azure-cli 
#		installed
#			Optional CLI: REMOTE_IMG=<docker-hub-image>
#
##############################################################
deploy:
	docker run -v $(PWD)/:/repo --entrypoint '/bin/bash' $(BUILD_IMG) \
		-c 'cd /repo && az login && az group create --name devTestGroup --location eastus && \
			az deployment group create --resource-group devTestGroup \
			--template-file azure/deploy-template.json \
			--parameter azure/deploy-parameters.json \
			--parameter imageName=$(REMOTE_IMG) \
			--parameter dnsNameLabel=$(URL)' 
	@$(info $(REMOTE_IMG) deployed to $(URL).eastus.azurecontainer.io)
	@$(info This may take a few minutes to respond)


##############################################################
#	make stop-deploy:
#		This stops the Azure container instances.
#
##############################################################
stop-deploy:
	docker run -v $(PWD)/:/repo --entrypoint '/bin/bash' $(BUILD_IMG) \
		-c 'cd /repo && az login && az group delete --name devTestGroup --yes'
