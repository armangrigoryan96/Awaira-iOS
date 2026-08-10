# Awaira for iPhone — build helpers.
#
# The Xcode project is generated from project.yml by XcodeGen; never edit
# Awaira.xcodeproj or Sources/Info.plist by hand, they are build artifacts.

SCHEME      := Awaira
PROJECT     := Awaira.xcodeproj
SIMULATOR   ?= iPhone 17
DESTINATION := platform=iOS Simulator,name=$(SIMULATOR)
BUNDLE_ID   := com.awaira.ios

# The real thing only works on a real iPhone — the simulator has no camera and no
# Picture-in-Picture. `make device` is the one that matters; override DEVICE with another UDID
# (`xcrun xctrace list devices`) to use a different phone.
DEVICE      ?= 00008030-00112C9C213A802E
TEAM        ?= XYA58M54V2
DEVICE_DEST := platform=iOS,id=$(DEVICE)

.PHONY: help install generate build test unit run device clean

help:
	@echo "make install   — install xcodegen (if needed), generate the project, build"
	@echo "make generate  — regenerate Awaira.xcodeproj from project.yml"
	@echo "make build     — build for the simulator"
	@echo "make test      — run unit + UI tests on '$(SIMULATOR)'"
	@echo "make unit      — run unit tests only (fast)"
	@echo "make run       — build, install and launch on '$(SIMULATOR)'"
	@echo "make device    — build, install and launch on the connected iPhone"
	@echo "make clean     — remove build artifacts and the generated project"

install:
	@command -v xcodegen >/dev/null || brew install xcodegen
	@$(MAKE) generate
	@$(MAKE) build

generate:
	xcodegen generate

build: generate
	xcodebuild build -project $(PROJECT) -scheme $(SCHEME) \
		-destination "$(DESTINATION)" | tail -20

test: generate
	xcodebuild test -project $(PROJECT) -scheme $(SCHEME) \
		-destination "$(DESTINATION)"

unit: generate
	xcodebuild test -project $(PROJECT) -scheme $(SCHEME) \
		-destination "$(DESTINATION)" -only-testing:AwairaTests

run: build
	@xcrun simctl boot "$(SIMULATOR)" 2>/dev/null || true
	@open -a Simulator
	@APP=$$(xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination "$(DESTINATION)" -showBuildSettings 2>/dev/null \
		| awk -F' = ' '/ BUILT_PRODUCTS_DIR /{d=$$2} / FULL_PRODUCT_NAME /{n=$$2} END{print d"/"n}'); \
	xcrun simctl install booted "$$APP" && \
	xcrun simctl launch booted $(BUNDLE_ID)

device: generate
	xcodebuild build -project $(PROJECT) -scheme $(SCHEME) \
		-destination "$(DEVICE_DEST)" -allowProvisioningUpdates \
		DEVELOPMENT_TEAM=$(TEAM) | tail -5
	@APP=$$(xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination "$(DEVICE_DEST)" -showBuildSettings 2>/dev/null \
		| awk -F' = ' '/ BUILT_PRODUCTS_DIR /{d=$$2} / FULL_PRODUCT_NAME /{n=$$2} END{print d"/"n}'); \
	xcrun devicectl device install app --device $(DEVICE) "$$APP" | grep -E 'App installed|bundleID'
	@xcrun devicectl device process launch --device $(DEVICE) \
		--terminate-existing $(BUNDLE_ID) | tail -1

clean:
	rm -rf build $(PROJECT) Sources/Info.plist
	xcodebuild clean -project $(PROJECT) -scheme $(SCHEME) 2>/dev/null || true
