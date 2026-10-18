# Fixed-source LibVLC SDK

The app currently uses the official Maven SDK unless a build explicitly selects
a custom AAR and its SHA-256. This directory prepares the native SDK migration;
adding a patch does not enable or publish it.

`source-lock.json` fixes the upstream commits, official AAR SHA-256, ordered
custom patches, complete native library/ABI set, compiler flags and container
digests. Every `.patch` under `patches/` must appear exactly once in the lock.
Custom patches apply to VLC after the 20 patches shipped with the fixed JNI
commit. Patch or toolchain changes require a new SDK and full app APK.

The upstream chain is:

- vlc-android `libvlc-3.7.7` → `7a7c8f14be6759f9bb1b9a934fd086259473e20e`.
- Its JNI snapshot is `0b8dc65efb203c86a0476bc337ddd99ecf1c0ef6`.
- JNI `buildsystem/get-vlc.sh` fixes VLC
  `84177b2273abc5c4300234e6e18b55a4d2dd5a03` and applies 20 official patches.

The parent release CI uses VideoLAN's `20260610055743` container for arm64 and
x86_64 (NDK 29.0.14206865), and `20260701183656` for armv7 (NDK 21.4.7075529).
The lock pins full image digests rather than mutable tags. These differ from
the newer 64-bit image used by the JNI repository's own CI.

GitHub container jobs explicitly run as UID 0 because the official image's
`videolan` UID 499 cannot own GitHub's workspace/home mounts. The locked
`FORCE_UNSAFE_CONFIGURE=1` is passed only to the SDK compiler so GNU build tools
can configure in that disposable container. It does not change host permissions
or system settings. Both the setting and effective UID appear in provenance.

Builds explicitly use `--release --license g`. Upstream's scripts default to
`g`; the actual official 3.7.7 native library's configure string includes
`--enable-live555 --enable-dvdread`, matching that branch. Selecting `a` would
disable GPL/GNUv3 contribs and alter the existing feature set. The Java POM's
LGPL-2.1 label is not a claim that every bundled native component is LGPL.
The SDK includes original notices and mixed upstream dependency licenses; it
does not rewrite the app's existing license. Release mode removes native debug
assertions; the official AAR's native configure string also contains debug mode.

## Build

From GitHub Actions, run **Build fixed-source LibVLC SDK** at the intended commit.
It prepares sources once, compiles the three ABIs independently in their fixed
containers, and only packages after all three builds succeed. Contribs build
from their locked source rules and upstream SHA-512 checksums; unavailable
prebuilt contrib archives are not used. No codecs, fonts or subtitle libraries
are removed beyond upstream's unchanged configuration/module blacklist.

For a local Linux amd64 build, the equivalent sequence is:

```bash
bash scripts/build-libvlc-sdk.sh prepare \
  --work-dir build/libvlc-sdk/work --output-dir build/libvlc-sdk/prepared
bash scripts/build-libvlc-sdk.sh plan
```

For each target printed by `plan`, unpack `prepared.tar.xz` into a **fresh**
working directory and run inside its locked image, with the repository mounted
at the same path:

```bash
# Set these from that target's source-lock.json entry.
docker run --rm --platform linux/amd64 \
  --user 0 \
  -e PRIVI_LIBVLC_BUILD_IMAGE="$SDK_IMAGE" \
  -v "$PWD:$PWD" -w "$PWD" "$SDK_IMAGE" \
  bash scripts/build-libvlc-sdk.sh build --abi "$SDK_ABI" --jobs 2 \
    --timeout-seconds 18000 --work-dir "$SDK_WORK" --output-dir "$SDK_PART"
```

Merge the disjoint `native/`, `abi/`, `licenses/`, and `source-parts/` output
directories from all three targets, then package using a fresh copy of the
prepared source snapshot:

```bash
bash scripts/build-libvlc-sdk.sh package \
  --work-dir build/libvlc-sdk/work --input-dir build/libvlc-sdk/parts \
  --output-dir build/libvlc-sdk/distribution
```

The result `libvlc-sdk.tar.xz` contains:

- `libvlc-privi.aar`: original official Java/resources, with **all** original
  `jni/` entries removed and replaced by the nine freshly built native files.
- `libvlc-corresponding-source.tar.xz`: patched VLC/JNI sources, build script,
  lock/patches, downloaded contrib/tool source archives, actual configure output
  and built-in module lists for each ABI. It also retains shallow public Git
  metadata and the pinned base AAR needed by the build, without app credentials.
- `libvlc-licenses.tar.xz`: notices captured from source dependencies and the
  selected NDK. C++ runtime comes from the same ABI build's NDK; NDK notices,
  revision and available LLVM source/cherry-pick references are retained.
- `libvlc-provenance.json` and `LIBVLC_SHA256SUMS`: project/source commits,
  patched tree, flags, container/NDK versions, dependency archives and native
  file hashes. The AAR also embeds its native build provenance.

The bundle has a separate SHA-256 sidecar. Archive metadata is normalized;
identical binary output across separate compiler runs is not yet established.
Build logs and failure status remain in per-ABI diagnostic artifacts. The
compiler has a five-hour hard timeout; matrix jobs have a 330-minute limit.
Existing nonempty outputs are rejected. The script only removes its own
temporary packaging directories; it never prunes shared Docker/build resources.

The corresponding-source archive is itself a prepared working directory. For a
source-offer rebuild, extract a fresh copy for each ABI and invoke its
`inputs/scripts/build-libvlc-sdk.sh build` in the locked container with
`--work-dir` pointing at that copy. Downloaded dependency archives are already
in the upstream contrib/tool cache paths. An app repository checkout is not
needed for that native rebuild.

## Select, validate, and publish

For temporary pre-release validation, set these workflow-dispatch inputs in
**Android Playback Validation** or **Release APK**:

- `sdk_run_id`: completed successful same-repository SDK workflow run.
- `sdk_commit`: its full source commit.
- `sdk_sha256`: SHA-256 of the **entire SDK bundle**, printed by the SDK workflow.

The downloader verifies the workflow path, repository, success, commit, bundle
hash, current source lock, all component checksums and native provenance. It
then sets `ORG_GRADLE_PROJECT_priviLibvlcAar` and
`ORG_GRADLE_PROJECT_priviLibvlcAarSha256`; Gradle independently verifies the AAR
and preserves the official POM's transitive dependencies. Invalid explicit
inputs fail; they never fall back to the old Maven SDK. An already signed
`release_run_id` cannot be combined with SDK inputs or have its libraries swapped.

SDK Actions artifacts expire. A custom-SDK app release therefore carries the
**same** SDK/source bundle, checksum and `LIBVLC_SDK_INPUT.json` through staged
validation and publishes them alongside the APK. Do not publicly release that
APK without these assets. Future builds can use the permanent public Release
asset URL as `sdk_url` (instead of `sdk_run_id`), keeping `sdk_commit` and the
bundle `sdk_sha256` fixed. The same paths are available locally through
`fetch-run` and `fetch-release`; their output prints the explicit Gradle inputs.

Building the SDK is not playback acceptance. Inspect the final APK's actual
native bytes/ABIs and signature, then run the existing real playback paths and
subtitle/PiP/first-playback acceptance before publication.

Upstream references: [parent release CI](https://code.videolan.org/videolan/vlc-android/-/blob/7a7c8f14be6759f9bb1b9a934fd086259473e20e/buildsystem/gitlab/.gitlab-ci.yml),
[JNI build flags](https://code.videolan.org/videolan/libvlcjni/-/blob/0b8dc65efb203c86a0476bc337ddd99ecf1c0ef6/buildsystem/compile-libvlc.sh),
[VLC checkout/official patches](https://code.videolan.org/videolan/libvlcjni/-/blob/0b8dc65efb203c86a0476bc337ddd99ecf1c0ef6/buildsystem/get-vlc.sh).
