#!/bin/bash
# Copyright 2023 Google LLC

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at

#     https://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
set -e

JAVA="java"
INPUT_ROOT="${1:-./source}"
DEST_AAB="${INPUT_ROOT}/out/mybundle.aab"
DEST_APK="${INPUT_ROOT}/out/mybundle.apk"

PACKAGE_NAME=$(xmllint --xpath 'string(//manifest/@package)' "${INPUT_ROOT}/AndroidManifest.xml")

java -jar dwf-format-1-validator-1.0.jar 1 source/res/raw/watchface.xml > valid.txt 2>&1

if grep -q 'PASSED' valid.txt; then
  echo Passed Validation!
else
  cat valid.txt
  exit 0
fi

rm -rf "${INPUT_ROOT}/out"
mkdir "${INPUT_ROOT}/out"

mkdir -p "${INPUT_ROOT}/out/compiled_resources"
aapt2 compile --dir "${INPUT_ROOT}/res" -o "${INPUT_ROOT}/out/compiled_resources/"

aapt2 link --proto-format -o "${INPUT_ROOT}/out/base.apk" \
-I "${ANDROID_JAR}" \
--manifest "${INPUT_ROOT}/AndroidManifest.xml" \
-R "${INPUT_ROOT}"/out/compiled_resources/*.flat \
--auto-add-overlay \
--rename-manifest-package "${PACKAGE_NAME}" \
--rename-resources-package "${PACKAGE_NAME}" \

unzip -q "${INPUT_ROOT}/out/base.apk" -d "${INPUT_ROOT}/out/base-apk/"

mkdir -p "${INPUT_ROOT}/out/aab-root/base/manifest/"

cp "${INPUT_ROOT}/out/base-apk/AndroidManifest.xml" "${INPUT_ROOT}/out/aab-root/base/manifest/"
cp -r "${INPUT_ROOT}/out/base-apk/res" "${INPUT_ROOT}/out/aab-root/base"
cp "${INPUT_ROOT}/out/base-apk/resources.pb" "${INPUT_ROOT}/out/aab-root/base"

(cd "${INPUT_ROOT}/out/aab-root/base" && zip ../base.zip -q -r -X .)

java -jar $ANDROID_HOME/bundletool-all-1.15.6.jar build-bundle --modules="${INPUT_ROOT}/out/aab-root/base.zip" --output="${DEST_AAB}"

jarsigner -keystore ${INPUT_ROOT}/my-release-key.jks ${DEST_AAB} key0

if [[ ! -z "${DEST_APK}" ]]; then
  if [[ -f "${INPUT_ROOT}/out/result.apks" ]]; then
    rm "${INPUT_ROOT}/out/result.apks"
  fi

  java -jar $ANDROID_HOME/bundletool-all-1.15.6.jar build-apks --bundle="${DEST_AAB}" --output="${INPUT_ROOT}/out/mybundle.apks" --mode=universal

  unzip "${INPUT_ROOT}/out/mybundle.apks" -d "${INPUT_ROOT}/out/result_apks/"

  zipalign -v -p 4 ${INPUT_ROOT}/out/result_apks/universal.apk ${INPUT_ROOT}/out/result_apks/universal-aligned-unsigned.apk

  apksigner sign --ks ${INPUT_ROOT}/my-release-key.jks --out ${INPUT_ROOT}/out/result_apks/universal-aligned-signed.apk ${INPUT_ROOT}/out/result_apks/universal-aligned-unsigned.apk
  
  cp "${INPUT_ROOT}/out/result_apks/universal-aligned-signed.apk" "${DEST_APK}"

else
  echo "Not building apks"
fi

java -jar memory-footprint.jar --watch-face source/out/mybundle.apk \
--schema-version 1 \
--ambient-limit-mb 10 \
--active-limit-mb 100 \
--apply-v1-offload-limitations \
--estimate-optimization 
