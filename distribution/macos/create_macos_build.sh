#!/bin/bash

set -e

function validate_directory {
    local dir=$1
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
    fi
    dir=$(readlink -f "$dir")
    echo "$dir"
}

function validate_file {
    local file=$1
    file=$(readlink -f "$file")
    if [ ! -f "$file" ]; then
        echo "File $file does not exist"
        exit 1
    fi
    echo "$file"
}

function check_command {
    local cmd=$1
    if ! command -v $cmd &> /dev/null; then
        echo "$cmd could not be found"
        exit 1
    fi
}

function execute_or_exit {
    local cmd=$1
    local error_msg=$2
    if ! $cmd; then
        echo "$error_msg"
        exit 1
    fi
}

if [ "$#" -lt 7 ]; then
    echo "usage <BASE_DIR> <TEMP_DIRECTORY> <OUTPUT_DIRECTORY> <ENTITLEMENTS_FILE_PATH> <VERSION> <SOURCE_REVISION_ID> <CONFIGURATION> <EXTRA_ARGS>"
    exit 1
fi

BASE_DIR=$(validate_directory "$1")
TEMP_DIRECTORY=$(validate_directory "$2")
OUTPUT_DIRECTORY=$(validate_directory "$3")
ENTITLEMENTS_FILE_PATH=$(validate_file "$4")
VERSION=$5
SOURCE_REVISION_ID=$6
CONFIGURATION=$7
EXTRA_ARGS=${8:-""}

RELEASE_TAR_FILE_NAME=""
if [ "$VERSION" == "1.1.0" ];
then
  RELEASE_TAR_FILE_NAME=test-ava-ryujinx-$CONFIGURATION-$VERSION+$SOURCE_REVISION_ID-macos_universal.app.tar
else
  RELEASE_TAR_FILE_NAME=test-ava-ryujinx-$VERSION-macos_universal.app.tar
fi

ARM64_APP_BUNDLE="$TEMP_DIRECTORY/output_arm64/Ryujinx.app"
X64_APP_BUNDLE="$TEMP_DIRECTORY/output_x64/Ryujinx.app"
UNIVERSAL_APP_BUNDLE="$OUTPUT_DIRECTORY/Ryujinx.app"
EXECUTABLE_SUB_PATH=Contents/MacOS/Ryujinx

rm -rf "$TEMP_DIRECTORY"
mkdir -p "$TEMP_DIRECTORY"

DOTNET_COMMON_ARGS="-p:DebugType=embedded -p:Version=$VERSION -p:SourceRevisionId=$SOURCE_REVISION_ID --self-contained true $EXTRA_ARGS"

execute_or_exit "dotnet restore" "dotnet restore failed"
execute_or_exit "dotnet build -c $CONFIGURATION src/Ryujinx.Ava" "dotnet build failed"
execute_or_exit "dotnet publish -c $CONFIGURATION -r osx-arm64 -o \"$TEMP_DIRECTORY/publish_arm64\" $DOTNET_COMMON_ARGS src/Ryujinx.Ava" "dotnet publish for arm64 failed"
execute_or_exit "dotnet publish -c $CONFIGURATION -r osx-x64 -o \"$TEMP_DIRECTORY/publish_x64\" $DOTNET_COMMON_ARGS src/Ryujinx.Ava" "dotnet publish for x64 failed"

# Get rid of the support library for ARMeilleure for x64 (that's only for arm64)
execute_or_exit "rm -rf \"$TEMP_DIRECTORY/publish_x64/libarmeilleure-jitsupport.dylib\"" "rm failed"

# Get rid of libsoundio from arm64 builds as we don't have a arm64 variant
# TODO: remove this once done
execute_or_exit "rm -rf \"$TEMP_DIRECTORY/publish_arm64/libsoundio.dylib\"" "rm failed"

pushd "$BASE_DIR/distribution/macos"
execute_or_exit "./create_app_bundle.sh \"$TEMP_DIRECTORY/publish_x64\" \"$TEMP_DIRECTORY/output_x64\" \"$ENTITLEMENTS_FILE_PATH\"" "create_app_bundle.sh failed for x64"
execute_or_exit "./create_app_bundle.sh \"$TEMP_DIRECTORY/publish_arm64\" \"$TEMP_DIRECTORY/output_arm64\" \"$ENTITLEMENTS_FILE_PATH\"" "create_app_bundle.sh failed for arm64"
popd

rm -rf "$UNIVERSAL_APP_BUNDLE"
mkdir -p "$OUTPUT_DIRECTORY"

# Let's copy one of the two different app bundle and remove the executable
execute_or_exit "cp -R \"$ARM64_APP_BUNDLE\" \"$UNIVERSAL_APP_BUNDLE\"" "cp failed"
execute_or_exit "rm \"$UNIVERSAL_APP_BUNDLE/$EXECUTABLE_SUB_PATH\"" "rm failed"

# Make it libraries universal
execute_or_exit "python3 \"$BASE_DIR/distribution/macos/construct_universal_dylib.py\" \"$ARM64_APP_BUNDLE\" \"$X64_APP_BUNDLE\" \"$UNIVERSAL_APP_BUNDLE\" \"**/*.dylib\"" "construct_universal_dylib.py failed"

if ! [ -x "$(command -v lipo)" ];
then
    if ! [ -x "$(command -v llvm-lipo-14)" ];
    then
        LIPO=llvm-lipo
    else
        LIPO=llvm-lipo-14
    fi
else
    LIPO=lipo
fi

# Make the executable universal
execute_or_exit "$LIPO \"$ARM64_APP_BUNDLE/$EXECUTABLE_SUB_PATH\" \"$X64_APP_BUNDLE/$EXECUTABLE_SUB_PATH\" -output \"$UNIVERSAL_APP_BUNDLE/$EXECUTABLE_SUB_PATH\" -create" "lipo failed"

# Get current year
CURRENT_YEAR=$(date +%Y)

# Patch up the Info.plist to have appropriate version
execute_or_exit "sed -r -i.bck \"s/\%\%RYUJINX_BUILD_VERSION\%\%/$VERSION/g;\" \"$UNIVERSAL_APP_BUNDLE/Contents/Info.plist\"" "sed failed"
execute_or_exit "sed -r -i.bck \"s/\%\%RYUJINX_BUILD_GIT_HASH\%\%/$SOURCE_REVISION_ID/g;\" \"$UNIVERSAL_APP_BUNDLE/Contents/Info.plist\"" "sed failed"
execute_or_exit "sed -r -i.bck \"s/\%\%CURRENT_YEAR\%\%/$CURRENT_YEAR/g;\" \"$UNIVERSAL_APP_BUNDLE/Contents/Info.plist\"" "sed failed for current year"
execute_or_exit "rm \"$UNIVERSAL_APP_BUNDLE/Contents/Info.plist.bck\"" "rm failed"

# Now sign it
if ! [ -x "$(command -v codesign)" ];
then
    check_command "rcodesign"
    echo "Using rcodesign for ad-hoc signing"
    execute_or_exit "rcodesign sign --entitlements-xml-path \"$ENTITLEMENTS_FILE_PATH\" \"$UNIVERSAL_APP_BUNDLE\"" "rcodesign failed"
else
    echo "Using codesign for ad-hoc signing"
    execute_or_exit "codesign --entitlements \"$ENTITLEMENTS_FILE_PATH\" -f --deep -s - \"$UNIVERSAL_APP_BUNDLE\"" "codesign failed"
fi

echo "Creating archive"
pushd "$OUTPUT_DIRECTORY"
execute_or_exit "tar --exclude \"Ryujinx.app/Contents/MacOS/Ryujinx\" -cvf $RELEASE_TAR_FILE_NAME Ryujinx.app 1> /dev/null" "tar failed"
execute_or_exit "python3 \"$BASE_DIR/distribution/misc/add_tar_exec.py\" $RELEASE_TAR_FILE_NAME \"Ryujinx.app/Contents/MacOS/Ryujinx\" \"Ryujinx.app/Contents/MacOS/Ryujinx\"" "add_tar_exec.py failed"
execute_or_exit "gzip -9 < $RELEASE_TAR_FILE_NAME > $RELEASE_TAR_FILE_NAME.gz" "gzip failed"
execute_or_exit "rm $RELEASE_TAR_FILE_NAME" "rm failed"
popd

echo "Done"
