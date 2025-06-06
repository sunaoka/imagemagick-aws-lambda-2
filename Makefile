PROJECT_ROOT = $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

DOCKER_IMAGE ?= public.ecr.aws/lambda/nodejs:22
TARGET ?=/opt/

MOUNTS = -v $(PROJECT_ROOT):/var/task \
	-v $(PROJECT_ROOT)result:$(TARGET)

DOCKER = docker run -it --rm -w=/var/task/build
build result: 
	mkdir $@

clean:
	rm -rf build result

list-formats:
	$(DOCKER) $(MOUNTS) --entrypoint /opt/bin/identify -t $(DOCKER_IMAGE) -list format

bash:
	$(DOCKER) $(MOUNTS) --entrypoint /bin/bash -t $(DOCKER_IMAGE)

all libs: 
	$(DOCKER) $(MOUNTS) --entrypoint /bin/sh -t $(DOCKER_IMAGE) -c "dnf install make gcc tar xz gcc-c++ cmake autoconf automake zlib-devel libtool -y && make -j$$(nproc) TARGET_DIR=$(TARGET) -f ../Makefile_ImageMagick $@"

STACK_NAME ?= imagemagick-layer 

result/bin/identify: all

build/layer.zip: result/bin/identify build
	# imagemagick has a ton of symlinks, and just using the source dir in the template
	# would cause all these to get packaged as individual files. 
	# (https://github.com/aws/aws-cli/issues/2900) 
	#
	# This is why we zip outside, using -y to store them as symlinks
	
	cd result && zip -ryT $(PROJECT_ROOT)$@ *

build/output.yaml: template.yaml build/layer.zip
	aws cloudformation package --template $< --s3-bucket $(DEPLOYMENT_BUCKET) --output-template-file $@

archive/layer.zip: build/layer.zip
	cp -p $< $@

deploy: build/output.yaml
	aws cloudformation deploy --template $< --stack-name $(STACK_NAME)
	aws cloudformation describe-stacks --stack-name $(STACK_NAME) --query Stacks[].Outputs --output table

deploy-example: deploy
	cd example && \
		make deploy DEPLOYMENT_BUCKET=$(DEPLOYMENT_BUCKET) IMAGE_MAGICK_STACK_NAME=$(STACK_NAME)
