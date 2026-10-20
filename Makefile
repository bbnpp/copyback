# SwiftPM 없이 swiftc를 직접 쓴다 (Xcode 없이 Command Line Tools만으로 빌드 가능)
APP_NAME := Copyback
BUILD    := build
APP      := $(BUILD)/$(APP_NAME).app
INSTALLED := /Applications/$(APP_NAME).app
SOURCES  := $(wildcard Sources/$(APP_NAME)/*.swift)
ARCH     := $(shell uname -m)
SWIFTC   := xcrun swiftc -sdk $(shell xcrun --show-sdk-path) -target $(ARCH)-apple-macos14.0 -swift-version 5

.PHONY: app test run install uninstall clean

app: $(APP)

$(APP): $(SOURCES) Resources/Info.plist
	@mkdir -p "$(APP)/Contents/MacOS"
	$(SWIFTC) -O $(SOURCES) -o "$(APP)/Contents/MacOS/$(APP_NAME)"
	cp Resources/Info.plist "$(APP)/Contents/Info.plist"
	codesign --force --sign - "$(APP)"

# 사용자 클립보드 대신 임시 pasteboard로 핵심 로직을 검사한다
test:
	@mkdir -p $(BUILD)
	$(SWIFTC) $(filter-out %/main.swift,$(SOURCES)) Tests/main.swift -o $(BUILD)/selftest
	$(BUILD)/selftest

run: app
	-pkill -x $(APP_NAME)
	open "$(APP)"

install: app
	-pkill -x $(APP_NAME)
	rm -rf "$(INSTALLED)"
	cp -R "$(APP)" /Applications/
	open "$(INSTALLED)"

uninstall:
	-pkill -x $(APP_NAME)
	rm -rf "$(INSTALLED)"

clean:
	rm -rf $(BUILD)
