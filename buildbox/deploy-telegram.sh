#!/bin/bash

set -e

CONFIGURATION="$1"

if [ -z "$CONFIGURATION" ]; then
	echo "Usage: sh deploy-telegram.sh CONFIGURATION"
	exit 1
fi

if [ ! `which setup-telegram-build.sh` ]; then
	echo "setup-telegram-build.sh not found in PATH $PATH"
	exit 1
fi

BASE_DIR=$(pwd)
BUILDBOX_DIR="buildbox"
mkdir -p "$BUILDBOX_DIR/transient-data"

source `which setup-telegram-build.sh`
setup_telegram_build "$CONFIGURATION" "$BASE_DIR/$BUILDBOX_DIR/transient-data"

COMMIT_ID=$(git rev-parse HEAD)
COMMIT_AUTHOR=$(git log -1 --pretty=format:'%an')
if [ -z "$2" ]; then
	COMMIT_COUNT=$(git rev-list --count HEAD)
	COMMIT_COUNT="$(($COMMIT_COUNT+1000))"
	BUILD_NUMBER="$COMMIT_COUNT"
else
	BUILD_NUMBER="$2"
fi

if [ "$CONFIGURATION" == "hockeyapp" ]; then
	FASTLANE_PASSWORD=""
	FASTLANE_ITC_TEAM_NAME=""
	FASTLANE_BUILD_CONFIGURATION="internalhockeyapp"
elif [ "$CONFIGURATION" == "appstore" ]; then
	FASTLANE_PASSWORD="$TELEGRAM_BUILD_APPSTORE_PASSWORD"
	FASTLANE_ITC_TEAM_NAME="$TELEGRAM_BUILD_APPSTORE_TEAM_NAME"
	FASTLANE_ITC_USERNAME="$TELEGRAM_BUILD_APPSTORE_USERNAME"
	FASTLANE_BUILD_CONFIGURATION="testflight_llc"
else
	echo "Unknown configuration $CONFIGURATION"
	exit 1
fi

OUTPUT_PATH="build/artifacts"
IPA_PATH="$OUTPUT_PATH/Telegram.ipa"
DSYM_PATH="$OUTPUT_PATH/Telegram.DSYMs.zip"

if [ ! -f "$IPA_PATH" ]; then
	echo "$IPA_PATH not found"
	exit 1
fi

if [ ! -f "$DSYM_PATH" ]; then
	echo "$DSYM_PATH not found"
	exit 1
fi

if [ "$1" == "appstore" ]; then
	export DELIVER_ITMSTRANSPORTER_ADDITIONAL_UPLOAD_PARAMETERS="-t DAV"
	FASTLANE_PASSWORD="$FASTLANE_PASSWORD" xcrun altool --upload-app --type ios --file "$IPA_PATH" --username "$FASTLANE_ITC_USERNAME" --password "@env:FASTLANE_PASSWORD"
	#FASTLANE_PASSWORD="$FASTLANE_PASSWORD" FASTLANE_ITC_TEAM_NAME="$FASTLANE_ITC_TEAM_NAME" fastlane "$FASTLANE_BUILD_CONFIGURATION" build_number:"$BUILD_NUMBER" commit_hash:"$COMMIT_ID" commit_author:"$COMMIT_AUTHOR" skip_build:1 skip_pilot:1
else
	FASTLANE_PASSWORD="$FASTLANE_PASSWORD" FASTLANE_ITC_TEAM_NAME="$FASTLANE_ITC_TEAM_NAME" fastlane "$FASTLANE_BUILD_CONFIGURATION" build_number:"$BUILD_NUMBER" commit_hash:"$COMMIT_ID" commit_author:"$COMMIT_AUTHOR" skip_build:1
fi
