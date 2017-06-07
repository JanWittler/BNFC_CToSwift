grammar ?= "CPP.cf"
outputPath ?= "./"
moduleName ?= "CGrammar"

SELF_DIR := $(dir $(lastword $(MAKEFILE_LIST)))

all: build

build: $(SELF_DIR)/BNFC_CToSwift $(SELF_DIR)/BNFC_CToSwift.xcodeproj
	xcodebuild -project $(SELF_DIR)"/BNFC_CToSwift.xcodeproj" 

run: build
	$(SELF_DIR)/build/Release/BNFC_CToSwift $(grammar) -o $(outputPath) -m $(moduleName)

clean:
	rm -rf $(SELF_DIR)/build/*.build
	rm -rf $(SELF_DIR)/build/Release/BNFC_CToSwift.dsym
	rm -rf $(SELF_DIR)/build/Release/BNFC_CToSwift.swiftmodule

mrproper-clean: clean
	rm -rf $(SELF_DIR)/build

	

