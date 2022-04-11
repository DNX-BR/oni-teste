export GOOGLE_IDP_ID?=C03jzkjg6
export GOOGLE_SP_ID?=331336665121
## Definir regiao do cluster
export AWS_DEFAULT_REGION?=us-east-2
export AWS_REGION?=$(AWS_DEFAULT_REGION)

## APP ENVIROMENTS APENAS QUANDO RODAR LOCAL
export APP_NAME?=oni
BUILD_VERSION?=latest

## Ambiente
ECR_ACCOUNT?=853246608662
PUBLIC_REPOSITORY?=public.ecr.aws/dnxbrasil
AWS_ACCOUNT_ID?=058100963274
AWS_ROLE?=dnxbrasilDNXAccess

ifdef CI
	ECR_REQUIRED=
else
	ECR_REQUIRED=ecrLogin
endif

GOOGLE_AUTH_IMAGE=dnxsolutions/aws-google-auth:0.0.37-dnx2
AWS_IMAGE=dnxsolutions/aws:latest

RUN_GOOGLE_AUTH=docker run --rm -it -e GOOGLE_USERNAME -e GOOGLE_IDP_ID -e GOOGLE_SP_ID -e AWS_ROLE_ARN -e AWS_DEFAULT_REGION --env-file=.env -v $(PWD)/.env.auth:/work/.env $(GOOGLE_AUTH_IMAGE)
RUN_AWS        =docker run --rm --env-file=.env.auth --env-file=.env.assume --env-file=.env -v $(PWD):/work --entrypoint "" $(AWS_IMAGE)
RUN_AWS_ROLE   =docker run --rm --env-file=.env --env-file=.env.auth -v $(PWD):/work --entrypoint "" $(AWS_IMAGE)


# export IMAGE_NAME=${PUBLIC_REPOSITORY}/${APP_NAME}:${BUILD_VERSION}
export IMAGE_NAME=${PUBLIC_REPOSITORY}/${APP_NAME}
# export IMAGE_NAME_LATEST=${PUBLIC_REPOSITORY}/${APP_NAME}:latest

env-%: # Check for specific environment variables
	@ if [ "${${*}}" = "" ]; then echo "Environment variable $* not set"; exit 1;fi

.env:
	cp .env.template .env
	echo >> .env
	touch .env.auth .env.assume

clean-dotenv:
	rm -f .env .env.assume

dnx-assume-ecr: clean-dotenv .env
	AWS_ACCOUNT_ID=$(ECR_ACCOUNT) \
	AWS_ROLE=$(AWS_ROLE) \
	$(RUN_AWS) assume-role.sh >> .env

assume-role: .env env-AWS_ACCOUNT_ID env-AWS_ROLE
	$(RUN_AWS_ROLE) assume-role.sh >> .env.assume
.PHONY: assume-role

assume-shell: assume-role
	docker run -it --rm --env-file=.env.assume -v $(PWD)\:/work --entrypoint "/bin/bash" $(AWS_IMAGE)
.PHONY: assume-shell

google-auth: .env env-GOOGLE_IDP_ID env-GOOGLE_SP_ID
	echo > .env.auth
	$(RUN_GOOGLE_AUTH)

ecrLogin: dnx-assume-ecr env-PUBLIC_REPOSITORY
	@echo "make ecrLogin"
	$(RUN_AWS) aws ecr-public get-login-password --region us-east-1 > .login
	rm -f ~/.docker/config.json
	cat .login | docker login --username AWS --password-stdin $(PUBLIC_REPOSITORY)
	rm -f .login

dockerBuild:
	@echo "make dockerBuild"
	docker build --target base --cache-from ${IMAGE_NAME}:base --tag ${IMAGE_NAME}:base -f Dockerfile  --build-arg BUILDKIT_INLINE_CACHE=1 .
	docker build --target base_debian --cache-from ${IMAGE_NAME}:base --cache-from ${IMAGE_NAME}:base_debian --tag ${IMAGE_NAME}:base_debian -f Dockerfile  --build-arg BUILDKIT_INLINE_CACHE=1 .
	docker build --cache-from ${IMAGE_NAME}:base --cache-from ${IMAGE_NAME}:base_debian --cache-from ${IMAGE_NAME}:latest --tag ${IMAGE_NAME}:${BUILD_VERSION} --tag ${IMAGE_NAME}:latest -f Dockerfile  --build-arg BUILDKIT_INLINE_CACHE=1 .

dockerPush:
	@echo "make dockerPush"
	docker push $(IMAGE_NAME):latest
	docker push $(IMAGE_NAME):${BUILD_VERSION}
