SHELL := /bin/zsh

PROJECT = RouseClosedLidHelper.xcodeproj
SCHEME = Rouse-Closed-Lid-Helper
CONFIGURATION ?= Release
ARCHIVE_PATH = build/RouseClosedLidHelper.xcarchive
EXPORT_PATH = build/export
APP_PATH = $(EXPORT_PATH)/Rouse Closed-Lid Helper.app
DMG_PATH = build/Rouse-Closed-Lid-Helper.dmg
NOTARY_ZIP = build/Rouse-Closed-Lid-Helper-notary.zip
ASC_XCODE_AUTH = set --; if [ -n "$$ASC_KEY_ID" ] && [ -n "$$ASC_ISSUER_ID" ] && [ -n "$$ASC_KEY_PATH" ]; then set -- -authenticationKeyPath "$$ASC_KEY_PATH" -authenticationKeyID "$$ASC_KEY_ID" -authenticationKeyIssuerID "$$ASC_ISSUER_ID"; echo "Using ASC API key for xcodebuild authentication"; fi;

.PHONY: generate lint build test archive export notarize-app package verify notarize release-artifact clean

generate:
	tuist generate --no-open

lint:
	swift scripts/lint_localizations.swift
	plutil -lint Entitlements/*.entitlements Support/LaunchDaemons/*.plist ExportOptions-DeveloperID.plist
	git diff --check

build: generate
	xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -configuration Debug build CODE_SIGNING_ALLOWED=NO

test: generate
	xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -configuration Debug test CODE_SIGNING_ALLOWED=NO

archive: generate
	rm -rf "$(ARCHIVE_PATH)"
	@$(ASC_XCODE_AUTH) xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -configuration "$(CONFIGURATION)" -archivePath "$(ARCHIVE_PATH)" archive -allowProvisioningUpdates "$$@" CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$${DEVELOPER_ID_APPLICATION:-Developer ID Application}"

export: archive
	rm -rf "$(EXPORT_PATH)"
	@$(ASC_XCODE_AUTH) xcodebuild -exportArchive -archivePath "$(ARCHIVE_PATH)" -exportPath "$(EXPORT_PATH)" -exportOptionsPlist ExportOptions-DeveloperID.plist -allowProvisioningUpdates "$$@"

notarize-app: export
	./scripts/notarize.sh "$(APP_PATH)"

package: notarize-app
	./scripts/create_dmg.sh "$(APP_PATH)" "$(DMG_PATH)"

notarize: package
	./scripts/notarize.sh "$(DMG_PATH)"

verify: notarize
	./scripts/verify_distribution.sh "$(APP_PATH)" "$(DMG_PATH)"

release-artifact: verify
	shasum -a 256 "$(DMG_PATH)" > "$(DMG_PATH).sha256"

clean:
	rm -rf build Derived "$(PROJECT)"
